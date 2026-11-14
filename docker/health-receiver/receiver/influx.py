"""Influx line protocol: naming, number/date coercion, point rendering.

Pure functions, no config, no I/O — this is the layer every translator writes
through, so a change here changes every measurement.
"""

import re
from datetime import datetime
from typing import Any

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
