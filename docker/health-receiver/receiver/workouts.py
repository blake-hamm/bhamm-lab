"""`health_workout` (one point per workout) and `health_workout_series`.

Workout payloads nest quantities as `{qty, units}`, hence quantity(); the
per-sample arrays (heartRateData, activeEnergy, ...) become their own
measurement tagged by workout id.
"""

from typing import TYPE_CHECKING, Any

from .config import SERIES_TYPES, WORKOUT_FIELDS
from .influx import as_number, camel_to_snake, line, parse_time_ns, point_time_ns

if TYPE_CHECKING:  # stream imports this module; import the type only
    from .stream import Stats

# Free-form nested structures; phase 2.
SKIPPED_SERIES = ("route", "events", "segments", "laps", "activities")


def quantity(obj: Any) -> float | None:
    """Nested `{qty,units}` or a bare number."""
    if isinstance(obj, dict):
        return as_number(obj.get("qty"))
    return as_number(obj)


def translate_workout(workout: dict, st: "Stats") -> None:
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


def translate_workout_series(workout: dict, st: "Stats") -> None:
    workout_id = workout.get("id") or ""
    for key, raw in workout.items():
        if not isinstance(raw, list) or not raw:
            continue
        if key in SKIPPED_SERIES:
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
