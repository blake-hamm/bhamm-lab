"""Static configuration: environment, endpoints, logging, field-name maps.

Everything here is read once at import time. Nothing in this module performs
I/O or inspects the payload.
"""

import logging
import os
import sys

import httpx

LOG = logging.getLogger("health-receiver")
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(logging.Formatter("%(levelname)s %(message)s"))
LOG.addHandler(_handler)
LOG.setLevel(logging.INFO)
LOG.propagate = False

INGEST_TOKEN = os.environ.get("INGEST_TOKEN", "")
VM_URL = os.environ.get(
    "VM_URL", "http://health-vm-victoria-metrics-single-server.health.svc:8428"
).rstrip("/")
WRITE_URL = f"{VM_URL}/write"
TIMEOUT = httpx.Timeout(30.0)

TOP_LEVEL_ARRAYS = (
    "metrics",
    "workouts",
    "stateOfMind",
    "medications",
    "symptoms",
    "cycleTracking",
    "ecg",
    "heartRateNotifications",
)
# Phase 1: counted, not stored. Each gets its own function when implemented.
UNSTORED_ARRAYS = (
    "stateOfMind",
    "medications",
    "symptoms",
    "cycleTracking",
    "ecg",
    "heartRateNotifications",
)

WORKOUT_FIELDS = {
    "duration": "duration",
    "activeEnergyBurned": "active_energy",
    "totalEnergy": "total_energy",
    "distance": "distance",
    "avgSpeed": "avg_speed",
    "maxSpeed": "max_speed",
    "elevationUp": "elevation_up",
    "elevationDown": "elevation_down",
    "intensity": "intensity",
    "temperature": "temperature",
    "humidity": "humidity",
    "avgHeartRate": "avg_hr",
    "maxHeartRate": "max_hr",
    "flightsClimbed": "flights_climbed",
    "swolfScore": "swolf_score",
    "totalSwimmingStrokeCount": "total_strokes",
    "swimCadence": "swim_cadence",
    "lapLength": "lap_length",
}

# Per-sample workout arrays. Any other array falls through to snake_case(name).
SERIES_TYPES = {
    "heartRateData": "heart_rate",
    "activeEnergy": "active_energy",
    "basalEnergy": "basal_energy",
    "cyclingCadence": "cycling_cadence",
    "cyclingDistance": "cycling_distance",
    "cyclingPower": "cycling_power",
    "cyclingSpeed": "cycling_speed",
    "swimDistance": "swim_distance",
    "swimStroke": "swim_stroke",
    "walkingAndRunningDistance": "walking_running_distance",
    "stepCount": "step_count",
}
