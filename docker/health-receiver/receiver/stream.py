"""Body bytes -> Influx lines, one metric/workout object at a time.

Streaming matters: a 13.7 MB export is ~92k points, and json.loads() peaks at
~591 MB RSS (43x the payload). ijson.items(..., 'data.metrics.item')
materialises exactly one metric object at a time.
"""

import io
from typing import Any, Iterator

import ijson

from .config import UNSTORED_ARRAYS
from .metrics import translate_metric
from .workouts import translate_workout

# How many leading items of an unstored array are sampled for key names.
SHAPE_SAMPLE = 5


class Stats:
    """Counters and accumulated lines for one request. Never logs values."""

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
            if count <= SHAPE_SAMPLE and isinstance(item, dict):
                keys |= {str(k) for k in item}
        if count:
            st.arrays[key] = count
            st.shapes.setdefault(key, set()).update(keys)
    if st.metric_entries:
        st.arrays["metrics"] = st.metric_entries
    return st.lines, st
