"""Request identity and process memory, so a dying request still leaves a line."""

import os
import threading
import time
import uuid

from .config import LOG

LIMIT_BYTES = int(os.environ.get("MEMORY_LIMIT_MIB", "1024")) * 1024 * 1024
HIGH_WATER = 0.80


def req_id() -> str:
    return uuid.uuid4().hex[:8]


def rss_mib() -> int:
    with open("/proc/self/statm", "rb") as fh:
        return int(fh.read().split()[1]) * os.sysconf("SC_PAGE_SIZE") // (1024 * 1024)


def peak_mib() -> int:
    import resource
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024


class Watchdog(threading.Thread):
    """Logs one memory_high line per crossing, at most once every 5 minutes."""

    def __init__(self, interval: float = 2.0) -> None:
        super().__init__(daemon=True, name="memory-watchdog")
        self.interval = interval
        self._last = 0.0

    def run(self) -> None:
        while True:
            time.sleep(self.interval)
            rss = rss_mib()
            if rss < LIMIT_BYTES * HIGH_WATER / (1024 * 1024):
                continue
            now = time.monotonic()
            if now - self._last < 300:
                continue
            self._last = now
            LOG.warning("memory_high rss_mib=%d peak_mib=%d", rss, peak_mib())
