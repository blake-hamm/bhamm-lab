"""Key-name-only view of a payload, for `?debug=1`. Never includes values."""

from .config import TOP_LEVEL_ARRAYS
from .stream import Stats

# The log line is truncated so one odd payload cannot flood stdout.
MAX_SHAPE_CHARS = 4000


def shape_dump(st: Stats) -> str:
    """Key-name-only view of the payload; never includes values."""
    parts = []
    for key in TOP_LEVEL_ARRAYS:
        if key in st.shapes:
            parts.append(f"{key}=[{','.join(sorted(st.shapes[key]))}]")
    for key in sorted(k for k in st.shapes if k.startswith("metrics.")):
        parts.append(f"{key}=[{','.join(sorted(st.shapes[key]))}]")
    return ("shape " + " ".join(parts))[:MAX_SHAPE_CHARS]
