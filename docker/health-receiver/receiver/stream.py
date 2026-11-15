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

    def skip(self, metric: str) -> None:
        self.skipped += 1
        key = metric or "unknown"
        self.skipped_types[key] = self.skipped_types.get(key, 0) + 1


def _items(body: bytes, prefix: str) -> Iterator[Any]:
    # use_float: without it ijson yields decimal.Decimal for every qty, which
    # costs memory and is not a float for as_number().
    return ijson.items(io.BytesIO(body), prefix, use_float=True)


def _count_arrays(body: bytes, st: Stats) -> None:
    """Count every item of the unstored arrays in ONE pass. Each of these used
    to be its own full ijson parse, so a body was parsed eight times."""
    wanted = {f"data.{key}.item" for key in UNSTORED_ARRAYS}
    counts = dict.fromkeys(UNSTORED_ARRAYS, 0)
    for prefix, event, _ in ijson.parse(io.BytesIO(body), use_float=True):
        if event == "start_map" and prefix in wanted:
            counts[prefix.split(".")[1]] += 1
    for key, count in counts.items():
        if count:
            st.arrays[key] = count


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
    _count_arrays(body, st)
    if st.metric_entries:
        st.arrays["metrics"] = st.metric_entries
    return st.lines, st
