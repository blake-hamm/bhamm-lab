"""Required-tag gate: refuse a document whose series cannot be attributed.

`line()` drops a tag whose value is None or empty, which is how a series can be
written with no attribution while the request still reports success. This check
runs at the request boundary, on the emitted lines, before the write.

Only the tags a measurement cannot function without are listed. `source`,
`unit`, `name`, `location` and friends stay optional on purpose: some metric
types genuinely have no unit, and requiring them would reject real traffic.
Measurements missing from the table pass through untouched.
"""

REQUIRED_TAGS: dict[str, tuple[str, ...]] = {
    "health_value": ("type",),
    "health_workout": ("id",),
    "health_workout_series": ("workout_id", "type"),
    "health_workout_split": ("workout_id", "type"),
    "health_workout_activity": ("workout_id", "type"),
}


def find_violation(lines: list[str]) -> tuple[str, str] | None:
    """First `(measurement, missing_tag)` in the lines, or None if all good.

    Only the head of the line (measurement + tag set) is parsed; fields and
    timestamp sit after the first space. A tag counts as missing when it is
    absent or its value is empty.
    """
    for raw in lines:
        head = raw.split(" ", 1)[0]
        measurement, _, tag_part = head.partition(",")
        required = REQUIRED_TAGS.get(measurement)
        if not required:
            continue
        present = {}
        for pair in tag_part.split(",") if tag_part else ():
            key, _, value = pair.partition("=")
            present[key] = value
        for tag in required:
            if not present.get(tag):
                return measurement, tag
    return None
