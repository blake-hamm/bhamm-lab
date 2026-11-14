"""`health_workout` (one point per workout), `health_workout_series`,
`health_workout_split` and `health_workout_activity`.

Workout payloads nest quantities as `{qty, units}`, hence quantity(); the
per-sample arrays (heartRateData, activeEnergy, ...) become their own
measurement tagged by workout id. Splits and activities instead nest a
free-form `metrics` object, so they emit one point per numeric metric keyed by
the metric's own name — a metric Apple adds later flows through untouched.
"""

from typing import TYPE_CHECKING, Any

from .config import SERIES_TYPES, WORKOUT_FIELDS
from .influx import as_number, camel_to_snake, line, parse_time_ns, point_time_ns

if TYPE_CHECKING:  # stream imports this module; import the type only
    from .stream import Stats

# Free-form nested structures; phase 2.
SKIPPED_SERIES = ("route", "events", "segments", "laps")
# Lists with a dedicated translator below; never the generic per-sample path.
NESTED_SERIES = ("splits", "activities")


def quantity(obj: Any) -> float | None:
    """Nested `{qty,units}` or a bare number."""
    if isinstance(obj, dict):
        return as_number(obj.get("qty"))
    return as_number(obj)


def nested_metrics(metrics: Any) -> dict[str, float]:
    """Numeric members of a nested `metrics` object, keyed by their own name.

    Agnostic on purpose: `paceMile`, `stepCadence` or anything new works with
    no code change here. Both `{qty,units}` and bare numbers are accepted.
    """
    if not isinstance(metrics, dict):
        return {}
    values: dict[str, float] = {}
    for name, raw in metrics.items():
        value = quantity(raw)
        if value is not None:
            values[str(name)] = value
    return values


def durations(entry: dict) -> dict[str, float | None]:
    """Item/activity timing, carried as extra fields on every metric point."""
    return {
        "active_duration": as_number(entry.get("activeDuration")),
        "elapsed_duration": as_number(entry.get("elapsedDuration")),
    }


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
    translate_splits(workout, st)
    translate_activities(workout, st)


def translate_workout_series(workout: dict, st: "Stats") -> None:
    workout_id = workout.get("id") or ""
    for key, raw in workout.items():
        if not isinstance(raw, list) or not raw:
            continue
        if key in SKIPPED_SERIES or key in NESTED_SERIES:
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


def translate_splits(workout: dict, st: "Stats") -> None:
    """One point per split item per numeric metric in the item's `metrics`.

    A split set is `{distanceType, boundaryOrigin, targetDistance, items[]}`;
    each item is one lap and its `metrics` is the per-mile/km pace breakdown.
    An absent or empty split list is normal (indoor/strength workout), not an error.
    """
    split_sets = workout.get("splits")
    if not isinstance(split_sets, list):
        return
    workout_id = workout.get("id") or ""
    for split_set in split_sets:
        if not isinstance(split_set, dict):
            st.skip("workout.splits")
            continue
        items = split_set.get("items")
        if not isinstance(items, list):
            st.skip("workout.splits")
            continue
        for item in items:
            if not isinstance(item, dict):
                st.skip("workout.splits")
                continue
            ts = parse_time_ns(item.get("start"))
            metrics = nested_metrics(item.get("metrics"))
            if ts is None or not metrics:
                st.skip("workout.splits")
                continue
            tags = {
                "workout_id": workout_id,
                "split_type": split_set.get("distanceType") or "",
                "split_kind": item.get("boundaryKind") or "",
                "split_origin": item.get("boundaryOrigin") or "",
                "partial": "true" if item.get("isPartial") else "false",
            }
            fields = durations(item)
            for name, value in metrics.items():
                st.lines.append(line(
                    "health_workout_split", {**tags, "type": name},
                    {"value": value, **fields}, ts,
                ))
                st.samples += 1
                st.types.add("workout.split")


def translate_activities(workout: dict, st: "Stats") -> None:
    """One point per activity per numeric metric in the activity's `metrics`."""
    activities = workout.get("activities")
    if not isinstance(activities, list):
        return
    workout_id = workout.get("id") or ""
    for activity in activities:
        if not isinstance(activity, dict):
            st.skip("workout.activities")
            continue
        ts = parse_time_ns(activity.get("start"))
        metrics = nested_metrics(activity.get("metrics"))
        if ts is None or not metrics:
            st.skip("workout.activities")
            continue
        configuration = activity.get("configuration") or {}
        location = configuration.get("locationType") if isinstance(configuration, dict) else None
        tags = {
            "workout_id": workout_id,
            "activity_type": activity.get("activityType") or "",
            "activity_type_code": activity.get("activityTypeCode") or "",
            "boundary_kind": activity.get("boundaryKind") or "",
            "location_type": location,
        }
        fields = durations(activity)
        for name, value in metrics.items():
            st.lines.append(line(
                "health_workout_activity", {**tags, "type": name},
                {"value": value, **fields}, ts,
            ))
            st.samples += 1
            st.types.add("workout.activity")
