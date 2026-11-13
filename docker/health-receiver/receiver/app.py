"""Health Auto Export (HAE) -> VictoriaMetrics receiver.

Replaces the retired Argo Events ingest path. HAE POSTs one JSON document; we
stream it with ijson, translate to Influx line protocol, and write it to
VictoriaMetrics in a SINGLE request. 2xx is returned ONLY after that write is
accepted: no queue, no retry loop, no buffering. If VictoriaMetrics is down the
caller gets a 502 and can see the failure.

Measurements written in phase 1:

  health_value          one point per metric sample (existing dashboard schema)
  health_workout        one point per workout, timestamp = start
  health_workout_series per-sample workout arrays (heart rate, energy, ...)
  health_workout_split  one point per split lap per nested metric (pace, ...)
  health_workout_activity one point per activity per nested metric

stateOfMind / medications / symptoms / cycleTracking / ecg /
heartRateNotifications are counted and reported but NOT stored yet; each one
gets its own translate_* function when it is added.
"""

import gzip
import hmac

import httpx
import ijson
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .config import INGEST_TOKEN, LOG, TIMEOUT, TOP_LEVEL_ARRAYS, WRITE_URL
from .shape import shape_dump
from .stream import Stats, lines_from_body

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
client = httpx.AsyncClient(timeout=TIMEOUT)


def authorized(request: Request) -> bool:
    header = request.headers.get("authorization") or ""
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not INGEST_TOKEN:
        return False
    return hmac.compare_digest(token.strip().encode(), INGEST_TOKEN.encode())


def arrays_log(st: Stats) -> str:
    return ",".join(f"{k}:{st.arrays[k]}" for k in TOP_LEVEL_ARRAYS if k in st.arrays)


@app.post("/")
async def ingest(request: Request):
    if not authorized(request):
        return JSONResponse({"error": "unauthorized"}, status_code=401)

    body = await request.body()  # no size cap by design
    try:
        lines, st = lines_from_body(body)
    except (ijson.JSONError, UnicodeDecodeError) as exc:
        reason = str(exc).splitlines()[0][:200] if str(exc) else type(exc).__name__
        LOG.warning("rejected bytes=%d reason=%s", len(body), reason)
        return JSONResponse({"error": "malformed json", "reason": reason}, status_code=400)

    # compresslevel pinned: CPython 3.15 changed gzip.compress's default from 9
    # to 6, which would inflate the wire payload (291k -> 344k on a real
    # export). Pinning keeps the bytes identical across interpreter upgrades.
    payload = gzip.compress("\n".join(lines).encode(), compresslevel=9)
    arrays = arrays_log(st)
    try:
        response = await client.post(
            WRITE_URL,
            content=payload,
            headers={"Content-Type": "text/plain", "Content-Encoding": "gzip"},
        )
    except httpx.HTTPError as exc:
        LOG.info(
            "failed bytes=%d samples=0 samples_skipped=%d types=%d workouts=%d "
            "arrays=%s upstream_error=%s",
            len(body), st.skipped, len(st.types), st.workouts, arrays,
            type(exc).__name__,
        )
        return JSONResponse(
            {"accepted": False, "error": "victoriametrics unreachable",
             "reason": type(exc).__name__},
            status_code=502,
        )

    if response.status_code // 100 != 2:
        LOG.info(
            "failed bytes=%d samples=0 samples_skipped=%d types=%d workouts=%d "
            "arrays=%s vm_status=%d",
            len(body), st.skipped, len(st.types), st.workouts, arrays,
            response.status_code,
        )
        return JSONResponse(
            {"accepted": False, "error": "victoriametrics rejected write",
             "vm_status": response.status_code, "vm_body": response.text[:500]},
            status_code=502,
        )

    LOG.info(
        "accepted bytes=%d samples=%d samples_skipped=%d types=%d workouts=%d arrays=%s",
        len(body), st.samples, st.skipped, len(st.types), st.workouts, arrays,
    )
    if st.skipped_types:
        LOG.info("skipped by type %s", ",".join(
            f"{k}:{v}" for k, v in sorted(st.skipped_types.items())))
    if (request.query_params.get("debug") or "") == "1":
        LOG.info(shape_dump(st))

    return JSONResponse({
        "accepted": True,
        "samples": st.samples,
        "samples_skipped": st.skipped,
        "types": len(st.types),
        "workouts": st.workouts,
        "bytes": len(body),
    })


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    # Deliberately does NOT probe VictoriaMetrics: a VM blip must surface as a
    # 502 on ingest, not as an unready pod hiding the failure.
    return {"status": "ready"}
