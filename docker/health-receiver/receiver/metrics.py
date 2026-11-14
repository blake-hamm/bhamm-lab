"""`health_value`: one line per metric sample (the existing dashboard schema).

Special-cased metrics are the ones whose payload is not a single `qty`:
heart_rate carries Avg/Min/Max, blood_pressure carries systolic/diastolic,
sexual_activity carries three boolean-ish fields, and sleep_analysis carries
the stage in `value` with the duration in `qty`. Everything else goes through
generic_fields().
"""

from typing import TYPE_CHECKING, Any

from .influx import as_number, line, parse_time_ns, point_time_ns, sanitize_name

if TYPE_CHECKING:  # stream imports this module; import the type only
    from .stream import Stats

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


def translate_metric(entry: dict, st: "Stats") -> None:
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
            present = [
                k
                for k in ("Unspecified", "Protection Used", "Protection Not Used")
                if k in point
            ]
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
