# Health stack

The iPhone app Health Auto Export (HAE) POSTs Apple Health JSON to `https://health-ingest.bhamm-lab.com/ingest` (bearer auth, Traefik `websecure` + wildcard TLS) on a 15-minute cadence; the `health-ingest` shim (`harbor.bhamm-lab.com/library/health-ingest:latest`, `kubernetes/manifests/apps/health/`, `docker/health-ingest/`) maps HAE type names via `mapping.yaml` (sleep durations rescaled seconds→hours) and writes Influx line protocol to single-node VictoriaMetrics in the `health` namespace (10y retention, 10Gi RWO PVC, `v1.155.0`) in one batched write per request; the result is queryable as `health_value{type=...}` in the "Health" dashboard in Grafana's **Extras** folder (datasource `health-vm`, both git-provisioned through `kube-prom-stack-all.yaml`), and Hermes reads it with PromQL through the existing read-only Grafana MCP (see [Monitoring](monitoring.md)). Nightly `vmbackup` (04:17 UTC CronWorkflow) snapshots the VM and uploads to `s3://health-vmbackup/<timestamp>` on Ceph RGW.

## Prerequisites / rollout order

1. **Vault token (blocking for any write).** Blake adds `ingest_token` under Vault/SOPS `/default/health` before the first write works — the `health` ExternalSecret (`/default/health` → `INGEST_TOKEN`) surfaces it to the shim, and the shim 401s every request until the token exists. No SOPS files are touched by the stack itself.
2. **HAE automation config.** Point HAE at `https://health-ingest.bhamm-lab.com/ingest` with the `Authorization: Bearer <ingest_token>` header and a 15-minute cadence.
3. **One-time full-history backfill.** Use HAE's manual export to POST the complete history to the same endpoint — the shim handles it identically (one batched VM write per request).

## Metric naming cookbook

Every sample lands as one Influx line: `health_value,type=<name>,source=<source> value=<v> <ns-timestamp>`. The value is always in the unit implied by the `type=` name; `source` is the sanitized HAE data-source name (e.g. `apple_health`, `ring`, `suunto`). HAE type names not in `mapping.yaml` pass through as `type=<sanitized-slug-of-name>`.

| HAE type name | `type=` | Notes |
|---|---|---|
| Heart Rate Variability | `hrv_ms` | |
| Resting Heart Rate | `rhr_bpm` | |
| Heart Rate | `heart_rate_bpm` | |
| Time in Bed | `sleep_hours` | HAE reports seconds → rescaled ÷3600 |
| Time in Awake | `awake_hours` | HAE reports seconds → rescaled ÷3600 |
| Oxygen Saturation | `spo2_pct` | |
| Body Mass | `weight_kg` | |
| Daily Steps / Total steps / Ring Steps / Suunto Steps | `steps` | see SUM-not-avg note below |
| Ring Sleep Score | `ring_sleep_score` | RingConn |
| eufy Air Quality | `aqi` | |
| eufy CO2 | `co2_ppm` | |
| eufy Temperature | `temperature_c` | |

**Steps is a SUM, not an average.** The `steps` value is the *cumulative total for the day* (Apple's "Daily Steps" resets daily; Apple, Ring, and Suunto all map to the same `type="steps"`). Do not `avg_over_time` it — that blends the day's ramp-up and double-counts sources. Take the last/max value instead, e.g. `max(health_value{type="steps"})`.

Example PromQL:

- 7-day HRV baseline:

  ```
  avg_over_time(health_value{type="hrv_ms"}[7d])
  ```

- z-score vs the 7-day baseline (sketch for a later readiness rule):

  ```
  (health_value{type="hrv_ms"} - avg_over_time(health_value{type="hrv_ms"}[7d]))
    / stddev_over_time(health_value{type="hrv_ms"}[7d])
  ```

- 7-day average sleep:

  ```
  avg_over_time(health_value{type="sleep_hours"}[7d])
  ```

## Restore drill

**DRILL REQUIRED before #394 can be closed.**

Outline (per <https://docs.victoriametrics.com/vmrestore/> — a single-node restore requires the VM stopped and an empty data path):

1. Stop the `health-vm` pod (the PVC is RWO, so the restore pod must run on the same node — same co-scheduling trick as the backup CronWorkflow's `podAffinity`).
2. Run `vmrestore` in a pod mounting `health-vm-data`, same image release and `health-vm-backup` secret as the backup:

   ```
   vmrestore \
     -src=s3://health-vmbackup/<timestamp> \
     -storageDataPath=/storage \
     -customS3Endpoint=http://external-rgw.ceph.svc.cluster.local:80
   ```

   (`docker.io/victoriametrics/vmrestore:v1.155.0`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from the secret; the RGW egress netpol already covers it.)
3. Start `health-vm` again; verify `GET /health` and one PromQL query through the `health-vm` datasource.
