"""Array counts per payload key, for `?debug=1`. Never includes values."""

from .config import TOP_LEVEL_ARRAYS
from .stream import Stats

# The log line is truncated so one odd payload cannot flood stdout.
MAX_SHAPE_CHARS = 4000


def shape_dump(st: Stats) -> str:
    """Key/count-only view of the payload; never includes values."""
    parts = [f"{key}={st.arrays[key]}" for key in TOP_LEVEL_ARRAYS if key in st.arrays]
    return ("shape " + " ".join(parts))[:MAX_SHAPE_CHARS]
