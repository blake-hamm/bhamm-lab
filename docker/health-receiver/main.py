"""Health Auto Export (HAE) -> VictoriaMetrics receiver.

Replaces the retired Argo Events ingest path. HAE POSTs one JSON document; we
stream it with ijson, translate to Influx line protocol, and write it to
VictoriaMetrics in a SINGLE request. 2xx is returned ONLY after that write is
accepted: no queue, no retry loop, no buffering. If VictoriaMetrics is down the
caller gets a 502 and can see the failure.

Streaming matters: a 13.7 MB export is ~92k points, and json.loads() peaks at
~591 MB RSS (43x the payload). ijson.items(..., 'data.metrics.item')
materialises exactly one metric object at a time.

Measurements written in phase 1:

  health_value          one point per metric sample (existing dashboard schema)
  health_workout        one point per workout, timestamp = start
  health_workout_series per-sample workout arrays (heart rate, energy, ...)

stateOfMind / medications / symptoms / cycleTracking / ecg /
heartRateNotifications are counted and reported but NOT stored yet; each one
gets its own translate_* function when it is added.
"""

import gzip
import hmac
import io
import json
import logging
import os
import re
import sys
from datetime import datetime
from typing import Any, Iterator

import httpx
import ijson
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

LOG = logging.getLogger("health-receiver")
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(logging.Formatter("%(levelname)s %(message)s"))
LOG.addHandler(handler)
LOG.setLevel(logging.INFO)
LOG.propagate = False

INGEST_TOKEN = os.environ.get("INGEST_TOKEN", "")
VM_URL = os.environ.get(
    "VM_URL", "http://health-vm-victoria-metrics-single-server.health.svc:8428"
).rstrip("/")
WRITE_URL = f"{VM_URL}/write"
TIMEOUT = httpx.Timeout(30.0)

TOP_LEVEL_ARRAYS = (
    "metrics",
    "workouts",
    "stateOfMind",
    "medications",
    "symptoms",
    "cycleTracking",
    "ecg",
    "heartRateNotifications",
)
# Phase 1: counted, not stored. Each gets its own function when implemented.
UNSTORED_ARRAYS = (
    "stateOfMind",
    "medications",
    "symptoms",
    "cycleTracking",
    "ecg",
    "heartRateNotifications",
)

WORKOUT_FIELDS = {
    "duration": "duration",
    "activeEnergyBurned": "active_energy",
    "totalEnergy": "total_energy",
    "distance": "distance",
    "avgSpeed": "avg_speed",
    "maxSpeed": "max_speed",
    "elevationUp": "elevation_up",
    "elevationDown": "elevation_down",
    "intensity": "intensity",
    "temperature": "temperature",
    "humidity": "humidity",
    "avgHeartRate": "avg_hr",
    "maxHeartRate": "max_hr",
    "flightsClimbed": "flights_climbed",
    "swolfScore": "swolf_score",
    "totalSwimmingStrokeCount": "total_strokes",
    "swimCadence": "swim_cadence",
    "lapLength": "lap_length",
}

# Per-sample workout arrays. Any other array falls through to snake_case(name).
SERIES_TYPES = {
    "heartRateData": "heart_rate",
    "activeEnergy": "active_energy",
    "basalEnergy": "basal_energy",
    "cyclingCadence": "cycling_cadence",
    "cyclingDistance": "cycling_distance",
    "cyclingPower": "cycling_power",
    "cyclingSpeed": "cycling_speed",
    "swimDistance": "swim_distance",
    "swimStroke": "swim_stroke",
    "walkingAndRunningDistance": "walking_running_distance",
    "stepCount": "step_count",
}

_NON_ALNUM = re.compile(r"[^a-z0-9]+")
_CAMEL = re.compile(r"(?<!^)(?=[A-Z])")


def sanitize_name(value: Any) -> str:
    """Lowercase [a-z0-9_]; everything else collapses to a single underscore."""
    return _NON_ALNUM.sub("_", str(value).lower()).strip("_")


def sanitize_tag_value(value: Any) -> str:
    """Tag value: escape backslash/comma/equals (spaces become underscores —
    `eufy Life` is a real source string, and the dashboards key on it)."""
    text = str(value).strip().replace(" ", "_")
    return text.replace("\\", "\\\\").replace(",", "\\,").replace("=", "\\=")


def camel_to_snake(name: str) -> str:
    return _CAMEL.sub("_", name).lower()


def as_number(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def fmt_float(value: float) -> str:
    return repr(float(value))


def parse_time_ns(value: Any) -> int | None:
    """`yyyy-MM-dd HH:mm:ss Z` per HAE (offset, no colon); ISO 8601 tolerated;
    epoch seconds when a bare number shows up (ECG voltages, notification
    samples)."""
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return int(float(value) * 1_000_000_000)
    if not isinstance(value, str) or not value:
        return None
    text = value.strip()
    try:
        dt = datetime.strptime(text, "%Y-%m-%d %H:%M:%S %z")
        return int(dt.timestamp() * 1_000_000_000)
    except ValueError:
        pass
    try:
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return int(dt.timestamp() * 1_000_000_000)


def point_time_ns(point: dict) -> int | None:
    ns = parse_time_ns(point.get("date"))
    if ns is None:
        ns = parse_time_ns(point.get("start"))
    return ns


def line(measurement: str, tags: dict, fields: dict, ts_ns: int) -> str:
    tag_part = "".join(
        f",{sanitize_name(k)}={sanitize_tag_value(v)}"
        for k, v in tags.items()
        if v not in (None, "")
    )
    field_part = ",".join(
        f"{sanitize_name(k)}={fmt_float(v)}" for k, v in fields.items() if v is not None
    )
    return f"{measurement}{tag_part} {field_part} {ts_ns}"


class Stats:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.samples = 0
        self.skipped = 0
        self.workouts = 0
        self.arrays: dict[str, int] = {}
        self.metrics: dict[str, int] = {}
        self.metric_entries = 0
        self.types: set[str] = set()
        self.skipped_types: dict[str, int] = {}
        self.shapes: dict[str, set[str]] = {}

    def skip(self, metric: str) -> None:
        self.skipped += 1
        key = metric or "unknown"
        self.skipped_types[key] = self.skipped_types.get(key, 0) + 1


# --------------------------------------------------------------------------- #
# health_value
# --------------------------------------------------------------------------- #


def translate_metric(entry: dict, st: Stats) -> None:
    raw_name = entry.get("name") or ""
    metric = sanitize_name(raw_name) or "unknown"
    units = entry.get("units") or ""
    data = entry.get("data")
    if not isinstance(data, list):
        st.skip(metric)
        return

    keys = st.shapes.setdefault(f"metrics.{metric}", set())
    for point in data[:5]:
        if isinstance(point, dict):
            keys |= {str(k) for k in point}

    for point in data:
        if not isinstance(point, dict):
            st.skip(metric)
            continue
        ts = point_time_ns(point)
        if ts is None:
            st.skip(metric)
            continue
        source = point.get("source") or ""
        tags = {"type": metric, "source": source, "unit": units}
        fields: dict[str, Any]

        if metric == "heart_rate":
            avg = as_number(point.get("Avg"))
            if avg is None:
                st.skip(metric)
                continue
            fields = {
                "value": avg,
                "min": as_number(point.get("Min")),
                "max": as_number(point.get("Max")),
            }
        elif metric == "blood_pressure":
            systolic = as_number(point.get("systolic"))
            if systolic is None:
                st.skip(metric)
                continue
            fields = {
                "value": systolic,
                "systolic": systolic,
                "diastolic": as_number(point.get("diastolic")),
            }
        elif metric == "sexual_activity":
            present = [k for k in ("Unspecified", "Protection Used", "Protection Not Used")
                       if k in point]
            if not present:
                st.skip(metric)
                continue
            used = as_number(point.get("Protection Used")) or 0.0
            fields = {
                "value": used,
                "unspecified": as_number(point.get("Unspecified")) or 0.0,
                "protection_used": used,
                "protection_not_used": as_number(point.get("Protection Not Used")) or 0.0,
            }
        elif metric == "sleep_analysis":
            hours = as_number(point.get("qty"))
            stage = point.get("value")
            if hours is None or not isinstance(stage, str):
                st.skip(metric)
                continue
            tags["stage"] = stage
            ts = parse_time_ns(point.get("start")) or ts
            fields = {"value": hours}
        else:
            fields = generic_fields(point)
            if not fields:
                st.skip(metric)
                continue

        st.lines.append(line("health_value", tags, fields, ts))
        st.samples += 1
        st.metrics[metric] = st.metrics.get(metric, 0) + 1
        st.types.add(metric)


GENERIC_PRIORITY = ("qty", "value", "count", "total", "Avg", "average")


def generic_fields(point: dict) -> dict[str, Any]:
    """qty wins; otherwise the first numeric field in a stable order."""
    numeric: dict[str, float] = {}
    for key, raw in point.items():
        if key in ("date", "start", "end", "startDate", "endDate"):
            continue
        num = as_number(raw)
        if num is not None:
            numeric[key] = num
    if not numeric:
        return {}
    ordered = [k for k in GENERIC_PRIORITY if k in numeric]
    ordered += sorted(k for k in numeric if k not in GENERIC_PRIORITY)
    fields: dict[str, Any] = {"value": numeric[ordered[0]]}
    for key in ordered[1:]:
        fields[key] = numeric[key]
    return fields


# --------------------------------------------------------------------------- #
# health_workout / health_workout_series
# --------------------------------------------------------------------------- #


def quantity(obj: Any) -> float | None:
    """Nested `{qty,units}` or a bare number."""
    if isinstance(obj, dict):
        return as_number(obj.get("qty"))
    return as_number(obj)


def translate_workout(workout: dict, st: Stats) -> None:
    st.shapes.setdefault("workouts", set()).update(str(k) for k in workout)
    start_ns = parse_time_ns(workout.get("start"))
    if start_ns is None:
        st.skip("workout")
        return
    tags = {
        "id": workout.get("id") or "",
        "name": workout.get("name") or "unknown",
        "location": workout.get("location") or "",
    }
    fields: dict[str, Any] = {}
    for key, field in WORKOUT_FIELDS.items():
        value = quantity(workout.get(key))
        if value is not None:
            fields[field] = value
    heart = workout.get("heartRate")
    if isinstance(heart, dict):
        for src, dest in (("min", "min_hr"), ("avg", "avg_hr"), ("max", "max_hr")):
            value = quantity(heart.get(src))
            if value is not None:
                fields.setdefault(dest, value)

    st.lines.append(line("health_workout", tags, fields, start_ns))
    st.samples += 1
    st.workouts += 1
    st.types.add("workout")
    translate_workout_series(workout, st)


def translate_workout_series(workout: dict, st: Stats) -> None:
    workout_id = workout.get("id") or ""
    for key, raw in workout.items():
        if not isinstance(raw, list) or not raw:
            continue
        if key in ("route", "events", "segments", "laps", "activities"):
            # Nested free-form structures; phase 2.
            continue
        series_type = SERIES_TYPES.get(key, camel_to_snake(key))
        for sample in raw:
            if not isinstance(sample, dict):
                st.skip(f"workout.{series_type}")
                continue
            ts = point_time_ns(sample)
            if ts is None:
                st.skip(f"workout.{series_type}")
                continue
            value = as_number(sample.get("qty"))
            if value is None:
                value = as_number(sample.get("Avg"))
            if value is None:
                value = as_number(sample.get("value"))
            if value is None:
                st.skip(f"workout.{series_type}")
                continue
            fields = {
                "value": value,
                "min": as_number(sample.get("Min")),
                "max": as_number(sample.get("Max")),
            }
            tags = {"workout_id": workout_id, "type": series_type}
            st.lines.append(line("health_workout_series", tags, fields, ts))
            st.samples += 1
            st.types.add(f"workout.{series_type}")


# --------------------------------------------------------------------------- #
# Streaming body -> line protocol
# --------------------------------------------------------------------------- #


def _items(body: bytes, prefix: str) -> Iterator[Any]:
    # use_float: without it ijson yields decimal.Decimal for every qty, which
    # costs memory and is not a float for as_number().
    return ijson.items(io.BytesIO(body), prefix, use_float=True)


def lines_from_body(body: bytes) -> tuple[list[str], Stats]:
    """One metric (or workout) object materialised at a time. Raises
    ijson.JSONError / UnicodeDecodeError on a malformed document."""
    st = Stats()
    for entry in _items(body, "data.metrics.item"):
        if isinstance(entry, dict):
            st.metric_entries += 1
            translate_metric(entry, st)
    for workout in _items(body, "data.workouts.item"):
        if isinstance(workout, dict):
            translate_workout(workout, st)
    for key in UNSTORED_ARRAYS:
        count = 0
        keys: set[str] = set()
        for item in _items(body, f"data.{key}.item"):
            count += 1
            if count <= 5 and isinstance(item, dict):
                keys |= {str(k) for k in item}
        if count:
            st.arrays[key] = count
            st.shapes.setdefault(key, set()).update(keys)
    if st.metric_entries:
        st.arrays["metrics"] = st.metric_entries
    return st.lines, st


def shape_dump(st: Stats) -> str:
    """Key-name-only view of the payload; never includes values."""
    parts = []
    for key in TOP_LEVEL_ARRAYS:
        if key in st.shapes:
            parts.append(f"{key}=[{','.join(sorted(st.shapes[key]))}]")
    for key in sorted(k for k in st.shapes if k.startswith("metrics.")):
        parts.append(f"{key}=[{','.join(sorted(st.shapes[key]))}]")
    return ("shape " + " ".join(parts))[:4000]


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #

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

    payload = gzip.compress("\n".join(lines).encode())
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
