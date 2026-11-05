"""health-ingest: Health Auto Export (HAE) webhook -> VictoriaMetrics.

Receives HAE JSON POSTs (Bearer-authenticated), maps health type names via
mapping.yaml, and writes Influx line protocol to VM in one batched request.
"""

import hmac
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request, Response

log = logging.getLogger("health-ingest")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

MAPPING_FILE = Path(__file__).resolve().parent / "mapping.yaml"

app = FastAPI(title="health-ingest")

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
SLUG_RE = re.compile(r"[^a-z0-9_]+")
SCALE_RE = re.compile(r"scale:\s*(\d+(?:/\d+)?|\d+\.\d+)")


class WriteError(Exception):
    """VM write failed after retry."""


def sanitize(name: str) -> str:
    """lowercase, [a-z0-9_], <= 40 chars."""
    return SLUG_RE.sub("_", name.lower()).strip("_")[:40]


def parse_mapping() -> dict:
    """Parse mapping.yaml (restricted line format, no YAML lib needed):

        "Type Name": metric_name  # scale: 1/3600
    """
    out = {}
    for raw in MAPPING_FILE.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        main_part, _, comment = line.partition(" #")
        m = re.match(r'^"(.+)"\s*:\s*(\S+)\s*$', main_part)
        if not m:
            continue
        name, metric = m.groups()
        scale = 1.0
        sm = SCALE_RE.search(comment)
        if sm:
            spec = sm.group(1)
            num, _, den = spec.partition("/")
            scale = float(num) / float(den or 1)
        out[name] = (metric, scale)
    return out


MAPPING = parse_mapping()


def ts_to_ns(date_str) -> int:
    """ISO8601 (offsets preserved) -> epoch nanoseconds; naive == UTC."""
    if not date_str:
        now = datetime.now(timezone.utc)
        return int((now - EPOCH) / timedelta(microseconds=1)) * 1000
    dt = datetime.fromisoformat(date_str)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int((dt - EPOCH) / timedelta(microseconds=1)) * 1000


def write_lines(lines: list[str]) -> None:
    """POST LP lines to VM /write. One retry; raise on final 5xx/connection failure."""
    url = os.environ["VM_URL"].rstrip("/") + "/write"
    payload = "\n".join(lines) + "\n"
    last_err = "unknown"
    for _ in range(2):
        try:
            r = httpx.post(
                url, content=payload, headers={"Content-Type": "text/plain"}, timeout=30.0
            )
            if r.status_code < 500:
                return
            last_err = f"VM HTTP {r.status_code}"
        except httpx.HTTPError as e:
            last_err = f"VM connection: {e}"
    raise WriteError(last_err)


@app.get("/healthz")
def healthz() -> Response:
    return Response(content="ok", media_type="text/plain")


@app.get("/mapping")
def mapping() -> Response:
    return Response(content=MAPPING_FILE.read_text(), media_type="text/yaml")


@app.post("/ingest")
async def ingest(request: Request):
    expected = os.environ.get("INGEST_TOKEN", "")
    auth = request.headers.get("authorization", "")
    if (
        not expected
        or not auth.startswith("Bearer ")
        or not hmac.compare_digest(auth[len("Bearer "):], expected)
    ):
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid JSON")
    data = body.get("data", {}) if isinstance(body, dict) else {}
    entries = data.get("Apple Health", data.get("HealthKit", []))
    if not isinstance(entries, list):
        entries = []

    lines: list[str] = []
    skipped = 0
    sources = set()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name", "")
        metric, scale = MAPPING.get(name, (sanitize(name), 1.0))
        source = sanitize(entry.get("dataSourceName") or "unknown")
        sources.add(source)
        for sample in entry.get("data") or []:
            v = sample.get("value")
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                skipped += 1
                continue
            lines.append(
                f"health_value,type={metric},source={source} "
                f"value={float(v) * scale} {ts_to_ns(sample.get('date'))}"
            )

    status = 200
    err = ""
    if lines:
        try:
            write_lines(lines)
        except WriteError as e:
            status = 502
            err = str(e)
    # One summary line per request; never log health values.
    log.info(
        "ingest source=%s metrics=%d status=%d",
        ",".join(sorted(sources)) or "none",
        len(lines),
        status,
    )
    if status == 502:
        raise HTTPException(status_code=502, detail=err)
    return {"status": "ok", "metrics": len(lines), "skipped": skipped}
