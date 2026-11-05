# health-ingest

Small FastAPI shim: receives Health Auto Export (HAE) JSON webhooks and writes them to VictoriaMetrics via Influx line protocol.

## Endpoints

- `POST /ingest` — HAE automation webhook target; requires `Authorization: Bearer <INGEST_TOKEN>` (constant-time compare). Body: HAE automation JSON (`data."Apple Health"` or `data."HealthKit"` array).
- `GET /healthz` → `ok`. `GET /mapping` → raw `mapping.yaml` (HAE config aid).

## Behavior

- Maps HAE type names via `mapping.yaml` (e.g. `Heart Rate Variability` → `hrv_ms`, `Time in Bed` → `sleep_hours`, seconds→hours); unknown names pass through as `health_value{type=<sanitized-slug>}` (lowercase, `[a-z0-9_]`, ≤40 chars).
- Influx LP: measurement `health_value`, tags `type` + `source` (sanitized `dataSourceName`), field `value`, timestamp ns from the ISO8601 date (offsets preserved; backfill OK — VM accepts past timestamps).
- One batched POST per request to `{VM_URL}/write` (one retry; 5xx propagates so HAE retries itself). One summary log line per request (source, metric count, status); health values are never logged.

## Env vars

- `INGEST_TOKEN` — bearer token HAE must present.
- `VM_URL` — VictoriaMetrics base URL, e.g. `http://health-vm.health.svc:8428`.

## Notes

- Idempotent: VM upserts by series + timestamp, so HAE re-POSTs of the same data are safe.
- Step counts are cumulative daily totals; sum (not overwrite) across sources when querying.
