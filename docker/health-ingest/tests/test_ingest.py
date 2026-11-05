"""health-ingest tests: HAE payload -> exact LP lines, auth, slug rule. No network."""

import main
from fastapi.testclient import TestClient

TOKEN = "test-token-123"

PAYLOAD = {
    "data": {
        "Apple Health": [
            {
                "name": "Heart Rate Variability",
                "units": "ms",
                "dataSourceName": "Apple Health",
                "data": [{"value": 42.5, "date": "2024-01-01T00:00:00Z"}],
            },
            {
                "name": "Resting Heart Rate",
                "units": "count/min",
                "dataSourceName": "Apple Health",
                "data": [{"value": 58, "date": "2024-01-01T00:30:00Z"}],
            },
            {
                "name": "Time in Bed",
                "units": "seconds",
                "dataSourceName": "Apple Watch",
                "data": [{"value": 25200, "date": "2024-01-01T06:00:00Z"}],
            },
            {
                "name": "Daily Steps",
                "units": "count",
                "dataSourceName": "Apple Watch",
                "data": [{"value": 9000, "date": "2024-01-01T23:00:00Z"}],
            },
            {
                "name": "Workout",
                "units": "seconds",
                "dataSourceName": "Apple Watch",
                "data": [{"value": 3600, "date": "2024-01-01T17:00:00Z"}],
            },
            {
                "name": "Fancy Unknown Metric\u2122",
                "units": "whatever",
                "dataSourceName": "Apple Health",
                "data": [{"value": 1.25, "date": "2024-01-01T12:00:00+02:00"}],
            },
        ]
    }
}

EXPECTED_LINES = [
    "health_value,type=fancy_unknown_metric,source=apple_health value=1.25 1704103200000000000",
    "health_value,type=hrv_ms,source=apple_health value=42.5 1704067200000000000",
    "health_value,type=rhr_bpm,source=apple_health value=58.0 1704069000000000000",
    "health_value,type=sleep_hours,source=apple_watch value=7.0 1704088800000000000",
    "health_value,type=steps,source=apple_watch value=9000.0 1704150000000000000",
    "health_value,type=workout,source=apple_watch value=3600.0 1704128400000000000",
]


def make_client(monkeypatch):
    monkeypatch.setenv("INGEST_TOKEN", TOKEN)
    monkeypatch.setenv("VM_URL", "http://vm.test:8428")
    return TestClient(main.app)


def test_401_no_token(monkeypatch):
    client = make_client(monkeypatch)
    r = client.post("/ingest", json=PAYLOAD)
    assert r.status_code == 401


def test_401_wrong_token(monkeypatch):
    client = make_client(monkeypatch)
    r = client.post(
        "/ingest", json=PAYLOAD, headers={"Authorization": "Bearer wrong"}
    )
    assert r.status_code == 401


def test_ingest_exact_lp_lines(monkeypatch):
    client = make_client(monkeypatch)
    captured = {}

    def fake_write(lines):
        captured["lines"] = lines

    monkeypatch.setattr(main, "write_lines", fake_write)
    r = client.post(
        "/ingest", json=PAYLOAD, headers={"Authorization": f"Bearer {TOKEN}"}
    )
    assert r.status_code == 200
    assert r.json()["skipped"] == 0
    assert sorted(captured["lines"]) == EXPECTED_LINES


def test_unknown_name_slug_rule(monkeypatch):
    client = make_client(monkeypatch)
    captured = {}
    monkeypatch.setattr(main, "write_lines", lambda lines: captured.update(lines=lines))
    r = client.post(
        "/ingest",
        json={
            "data": {
                "Apple Health": [
                    {
                        "name": "Fancy Unknown Metric\u2122",
                        "dataSourceName": "Apple Health",
                        "data": [{"value": 1.25, "date": "2024-01-01T12:00:00+02:00"}],
                    }
                ]
            }
        },
        headers={"Authorization": f"Bearer {TOKEN}"},
    )
    assert r.status_code == 200
    assert (
        captured["lines"]
        == [
            "health_value,type=fancy_unknown_metric,source=apple_health value=1.25 1704103200000000000"
        ]
    )


def test_healthkit_fallback(monkeypatch):
    client = make_client(monkeypatch)
    captured = {}
    monkeypatch.setattr(main, "write_lines", lambda lines: captured.update(lines=lines))
    payload = {"data": {"HealthKit": PAYLOAD["data"]["Apple Health"]}}
    r = client.post(
        "/ingest", json=payload, headers={"Authorization": f"Bearer {TOKEN}"}
    )
    assert r.status_code == 200
    assert sorted(captured["lines"]) == EXPECTED_LINES


def test_non_numeric_values_skipped(monkeypatch):
    client = make_client(monkeypatch)
    captured = {}
    monkeypatch.setattr(main, "write_lines", lambda lines: captured.update(lines=lines))
    payload = {
        "data": {
            "Apple Health": [
                {
                    "name": "Heart Rate",
                    "dataSourceName": "Apple Health",
                    "data": [
                        {"value": "not-a-number", "date": "2024-01-01T00:00:00Z"},
                        {"value": 72, "date": "2024-01-01T00:00:00Z"},
                    ],
                }
            ]
        }
    }
    r = client.post(
        "/ingest", json=payload, headers={"Authorization": f"Bearer {TOKEN}"}
    )
    assert r.status_code == 200
    assert r.json()["skipped"] == 1
    assert captured["lines"] == [
        "health_value,type=heart_rate_bpm,source=apple_health value=72.0 1704067200000000000"
    ]


def test_vm_5xx_propagates(monkeypatch):
    client = make_client(monkeypatch)

    def boom(lines):
        raise main.WriteError("VM HTTP 503")

    monkeypatch.setattr(main, "write_lines", boom)
    r = client.post(
        "/ingest", json=PAYLOAD, headers={"Authorization": f"Bearer {TOKEN}"}
    )
    assert r.status_code == 502


def test_healthz_and_mapping(monkeypatch):
    client = make_client(monkeypatch)
    assert client.get("/healthz").text == "ok"
    m = client.get("/mapping")
    assert m.status_code == 200
    assert '"Heart Rate Variability": hrv_ms' in m.text
