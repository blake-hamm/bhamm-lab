# Monitoring

Stack is `kube-prometheus-stack` 77.14.0 (Grafana subchart 10.0.0), deployed via Argo Application `kube-prometheus-stack` (`kubernetes/manifests/base/monitor/kube-prom-stack-all.yaml`) into the `monitor` namespace.

- **Prometheus:** 15d retention, 25Gi RWO PVC (RBD CSI), deliberately **not** k8up-backed — restoring stale time-series wedges Prometheus on timing, so recovery is retention + git re-provisioning
- **Alertmanager:** `alertmanager.bhamm-lab.com`
- **Grafana:** 12.1.1, `grafana.bhamm-lab.com` — Traefik ingress behind Authelia (generic OAuth, auto-login, `auto_assign_org_role: Viewer`)
- **Loki:** distributed, gateway at `http://loki-distributed-gateway` (Grafana datasource, proxy access)
- **Dashboards:** re-provisioned from git via the sidecar (`grafana_dashboard: "1"` label) plus `extra-dashboards` (URL + gnet sources, `disableDeletion: true`)

## Persistence

Grafana state (service accounts, tokens, alerting contact points, provisioning) lives on a 5Gi RWO PVC (RBD CSI, cluster-default storage class — no `storageClassName` set, same as Prometheus). The `monitor` namespace enables k8up backups via the common chart (`k8up.backup.enabled: true`), which — with the k8up operator's `skipWithoutAnnotation` — covers the Grafana PVC (annotated `k8up.io/backup: "true"`) only; the Prometheus volume is intentionally out of the backup set, and the k8up restore workflow is intentionally not enabled yet. Before this change Grafana used an emptyDir and every pod recreation wiped UI-created state — the `forge-agent` service account and token below depend on persistence.

## Agent observability access (Grafana MCP)

The forge Hermes profile has read-only access to Grafana through the `mcp-grafana` MCP server.

- **Service account:** `forge-agent`, org role **Viewer** (the hard read-only boundary on the API side). Created once in the Grafana UI after the persistence change landed; the token persists via the PVC.
- **Token path:** SOPS `/core/monitor` key `grafana_service_account_token` → Vault → hermes `ExternalSecret` → container env `GRAFANA_SERVICE_ACCOUNT_TOKEN` (`secretKeyRef` is `optional: true` until the token exists; the MCP server simply fails to authenticate until then). Hermes passes only a sanitized env to MCP subprocesses — pod env vars do not reach `mcp-grafana` — so during bootstrap the token is extracted from the hermes secret/pod env into `/opt/data/profiles/forge/secrets/grafana_service_account_token` (mode 600), and the MCP subprocess receives it via `GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE` pointing at that file; the file is re-read per request, so token rotation works without a restart.
- **MCP server:** stdio subprocess in the forge profile:

  ```
  uvx mcp-grafana@2.1.1 --disable-write --loki-guardrail-mode=enforce --loki-guardrail-max-range=24h --usage-stats=disabled
  ```

  with `GRAFANA_URL=http://kube-prometheus-stack-grafana.monitor.svc:80`. `--disable-write` unregisters all write tools client-side; `--usage-stats=disabled` opts out of mcp-grafana's default anonymous usage stats to Grafana Labs; the Viewer role is the API-side hard boundary; all queries go through Grafana's datasource proxy (single credential, full audit trail in the Grafana access log). Egress to the Grafana pod is allowed by the hermes CiliumNetworkPolicy.
- **Trust boundary:** log content (Loki/Prometheus) is untrusted input — a prompt-injection surface. Read-only access plus gitops-only writes are the mitigation.

### Recovery

This section is the source of truth if the pod/PVC is ever rebuilt.

1. **SA + token.** Both persist in the Grafana PVC. If the PVC is lost: recreate the `forge-agent` service account (Viewer) in the Grafana UI, add the token to SOPS `/core/monitor` as `grafana_service_account_token`, commit, wait for SOPS→Vault sync + ExternalSecret refresh, restart the hermes pod. After the ExternalSecret refresh, re-extract the token into `/opt/data/profiles/forge/secrets/grafana_service_account_token` (`printf '%s' "$TOKEN" > /opt/data/profiles/forge/secrets/grafana_service_account_token && chmod 600`) — never echo the token into logs.
2. **forge profile config:**

   ```yaml
   mcp_servers:
     grafana:
       command: uvx
       args: ["mcp-grafana@2.1.1", "--disable-write", "--loki-guardrail-mode=enforce", "--loki-guardrail-max-range=24h", "--usage-stats=disabled"]
       env:
         GRAFANA_URL: "http://kube-prometheus-stack-grafana.monitor.svc:80"
         GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE: "/opt/data/profiles/forge/secrets/grafana_service_account_token"
       timeout: 120
   ```

3. **Proof of life:** `GET /api/access-control/user/permissions` with the token shows zero write actions; run one LogQL and one PromQL query via the MCP tools.
