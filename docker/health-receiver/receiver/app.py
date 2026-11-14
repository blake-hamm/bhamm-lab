"""Health Auto Export (HAE) -> VictoriaMetrics receiver.

Replaces the retired Argo Events ingest path. HAE POSTs one JSON document; we
stream it with ijson, translate to Influx line protocol, and write it to
VictoriaMetrics in a SINGLE request. 2xx is returned ONLY after that write is
accepted: no queue, no buffering. If VictoriaMetrics stays down the caller gets
a 502 and can see the failure.

Two guards sit in front of that write. A document with an unattributable series
is refused with 422 before anything is sent. A connection-level failure or a 5xx
is retried twice (0.5s, 1.0s); a 4xx never is.

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

import asyncio
import gzip
import hmac

import httpx
import ijson
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .config import INGEST_TOKEN, LOG, TIMEOUT, TOP_LEVEL_ARRAYS, WRITE_URL
from .shape import shape_dump
from .stream import Stats, lines_from_body
from .validate import find_violation

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
client = httpx.AsyncClient(timeout=TIMEOUT)

WRITE_HEADERS = {"Content-Type": "text/plain", "Content-Encoding": "gzip"}
# Sleep before attempt 2 and attempt 3. A 4xx is never retried: the request is
# malformed and would fail identically, so the error has to surface.
RETRY_DELAYS = (0.5, 1.0)
RETRY_ERRORS = (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout)


async def write(payload: bytes) -> httpx.Response:
    """POST the body, retrying connection failures and 5xx up to 3 attempts."""
    attempt = 1
    while True:
        try:
            response = await client.post(WRITE_URL, content=payload, headers=WRITE_HEADERS)
        except RETRY_ERRORS as exc:
            if attempt > len(RETRY_DELAYS):
                raise
            LOG.warning("retry attempt=%d error=%s", attempt, type(exc).__name__)
        else:
            if response.status_code // 100 != 5 or attempt > len(RETRY_DELAYS):
                return response
            LOG.warning("retry attempt=%d status=%d", attempt, response.status_code)
        await asyncio.sleep(RETRY_DELAYS[attempt - 1])
        attempt += 1


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

    # Refuse an unattributable series here: line() would silently drop the
    # empty tag and the write would still return 200.
    violation = find_violation(lines)
    if violation:
        measurement, tag = violation
        LOG.warning("rejected missing_tag measurement=%s tag=%s", measurement, tag)
        return JSONResponse(
            {"accepted": False, "error": "missing required tag",
             "measurement": measurement, "tag": tag},
            status_code=422,
        )

    # compresslevel pinned: CPython 3.15 changed gzip.compress's default from 9
    # to 6, which would inflate the wire payload (291k -> 344k on a real
    # export). Pinning keeps the bytes identical across interpreter upgrades.
    payload = gzip.compress("\n".join(lines).encode(), compresslevel=9)
    arrays = arrays_log(st)
    try:
        response = await write(payload)
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
