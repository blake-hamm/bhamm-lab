# NixOS Monitoring Implementation Plan

## Objective
Add Prometheus metrics and Loki logging to all NixOS hosts using a reusable NixOS module. This replaces the Ansible-managed exporters on Debian nodes with a declarative, Nix-native approach that scales across the entire NixOS fleet.

## Scope
- **Garage** (`garage`, `10.0.20.21`, server) — full parity with Debian nodes + Garage-native metrics
- **Tail** (`tail`, `10.0.30.79`, server) — full parity with Debian nodes
- **Orange Pi Zero 3** (`orangepi-zero3`, `10.0.9.3`, SBC) — node + systemd + promtail
- **Orange Pi Zero 3 Backup** (`orangepi-zero3-backup`, `10.0.9.4`, SBC) — node + systemd + promtail
- **Framework** (`framework`, `10.0.80.2`, desktop) — **excluded** (mobile, trusted VLAN, intermittent connectivity)

## Architecture

### NixOS Side
A new `monitoring.nix` module under `nix/modules/services/` provides a single `cfg.monitoring` option tree. Each profile (`server.nix`, `sbc.nix`) opts in at the appropriate level. Exporters bind to `0.0.0.0` and use `openFirewall = true`. Network-level access control is enforced by OPNsense VLAN rules, not host firewalls.

### Prometheus Side
The cluster-hosted Prometheus (`kube-prometheus-stack`) scrapes NixOS targets via `additionalScrapeConfigs`. Garage admin metrics (`/metrics`) are exposed on port `3903` unauthenticated (VLAN-segmented).

### Loki Side
Promtail on each NixOS host reads the systemd journal and pushes to `https://loki.bhamm-lab.com/loki/api/v1/push`. No host-side log files are tailed; journald is the single source of truth.

---

## Files to Create / Modify

### 1. `nix/modules/services/monitoring.nix` (NEW)

A declarative module that wraps Prometheus exporters and Promtail.

**Options tree:**
```nix
cfg.monitoring = {
  enable                  # Master switch (bool, default false)
  nodeExporter = {
    enable                # bool, default true when monitoring.enable
    port                  # int, default 9100
  }
  systemdExporter = {
    enable                # bool, default true when monitoring.enable
    port                  # int, default 9558
  }
  smartctlExporter = {
    enable                # bool, default true when monitoring.enable
    port                  # int, default 9633
  }
  promtail = {
    enable                # bool, default true when monitoring.enable
    lokiUrl               # string, default "https://loki.bhamm-lab.com/loki/api/v1/push"
  }
}
```

**Implementation details:**
- `services.prometheus.exporters.node` — enable, set port, `enabledCollectors = [ "systemd" ]`, `openFirewall = true`
- `services.prometheus.exporters.systemd` — enable, set port, `openFirewall = true`
- `services.prometheus.exporters.smartctl` — enable, set port, `openFirewall = true`
- `services.promtail` — enable with journald scrape config, push to `lokiUrl`
- Firewall: rely on `openFirewall` per-exporter; do not duplicate in `networking.firewall`

**Notes:**
- `smartctl_exporter` should not be enabled on hosts without SMART-capable disks (e.g. SBCs with SD cards, laptops with NVMe/SSD if undesired).
- The module uses `lib.mkDefault` so profiles can easily override individual exporters.

---

### 2. `nix/modules/services/default.nix` (MODIFY)

Add `./monitoring.nix` to the imports list.

```nix
{
  imports = [
    ./backups.nix
    ./docker.nix
    ./monitoring.nix    # NEW
    ./nut.nix
    ./pihole.nix
    ./pre-commit.nix
    ./samba.nix
    ./virtualization.nix
    ./keepalived.nix
  ];
}
```

---

### 3. `nix/profiles/server.nix` (MODIFY)

Enable full monitoring for server-class hosts.

```nix
{
  imports = [
    ../modules
  ];

  cfg = {
    networking.backend = "networkd";
    monitoring.enable = true;    # NEW — enables node, systemd, smartctl, promtail
  };
}
```

**Hosts affected:** `garage`, `tail`

---

### 4. `nix/profiles/sbc.nix` (MODIFY)

Enable monitoring for SBC hosts, but disable `smartctlExporter` (SD/eMMC cards lack SMART).

```nix
{ lib, ... }:
{
  imports = [
    ../modules
  ];

  # SBC-specific defaults
  cfg = {
    networking.backend = "networkd";
    gnome.enable = lib.mkDefault false;
    docker.enable = lib.mkDefault false;
    kitty.enable = lib.mkDefault false;
    vscode.enable = lib.mkDefault false;
    uhk.enable = lib.mkDefault false;
    vesktop.enable = lib.mkDefault false;

    monitoring.enable = true;                        # NEW
    monitoring.smartctlExporter.enable = false;      # NEW — SBCs use SD/eMMC
  };
}
```

**Hosts affected:** `orangepi-zero3`, `orangepi-zero3-backup`

---

### 5. `nix/hosts/garage/garage.nix` (MODIFY)

Two changes:

**a) Bind Garage admin API externally for metrics scraping:**

Change:
```nix
admin.api_bind_addr = "127.0.0.1:3903";
```
To:
```nix
admin.api_bind_addr = "0.0.0.0:3903";
```

**b) Open firewall for admin metrics port** (if not relying solely on `openFirewall` from the monitoring module for other ports). Since the monitoring module handles 9100/9558/9633 via `openFirewall`, only 3903 (Garage admin) needs explicit firewall rules here.

Replace existing:
```nix
networking.firewall.allowedTCPPorts = [ 3900 ];
```
With:
```nix
networking.firewall.allowedTCPPorts = [
  3900   # S3 API (existing)
  3903   # Garage admin /metrics (NEW)
];
```

**Note:** The `monitoring.nix` module will open 9100/9558/9633 automatically via `openFirewall = true` on each exporter.

---

### 6. `kubernetes/manifests/base/monitor/kube-prom-stack-all.yaml` (MODIFY)

Add NixOS targets to `prometheusSpec.additionalScrapeConfigs`.

#### 6a. `nodes` job — add garage and tail

```yaml
- job_name: 'nodes'
  static_configs:
    - targets:
        - '10.0.20.11:9100'  # Method
        - '10.0.20.12:9100'  # Indy
        - '10.0.20.15:9100'  # Japan
        - '10.0.20.21:9100'  # Garage (NEW)
        - '10.0.30.79:9100'  # Tail (NEW)
```

#### 6b. `garage` job — scrape Garage native metrics

```yaml
- job_name: 'garage'
  static_configs:
    - targets:
        - '10.0.20.21:3903'
```

No `authorization` section needed — metrics endpoint is unauthenticated (VLAN-segmented).

#### 6c. `smartctl` job — add garage and tail

```yaml
- job_name: 'smartctl'
  scrape_interval: 1m
  static_configs:
    - targets:
        - '10.0.20.11:9633'  # Method
        - '10.0.20.12:9633'  # Indy
        - '10.0.20.15:9633'  # Japan
        - '10.0.20.21:9633'  # Garage (NEW)
        - '10.0.30.79:9633'  # Tail (NEW)
```

#### 6d. `systemd` job — add garage and tail

```yaml
- job_name: 'systemd'
  static_configs:
    - targets:
        - '10.0.20.11:9558'  # Method
        - '10.0.20.12:9558'  # Indy
        - '10.0.20.15:9558'  # Japan
        - '10.0.20.21:9558'  # Garage (NEW)
        - '10.0.30.79:9558'  # Tail (NEW)
```

#### 6e. (Optional) Orange Pi targets

If scraping Orange Pi hosts is desired, extend the jobs further:

```yaml
- job_name: 'nodes'
  static_configs:
    - targets:
        # ... existing ...
        - '10.0.9.3:9100'   # orangepi-zero3
        - '10.0.9.4:9100'   # orangepi-zero3-backup

- job_name: 'systemd'
  static_configs:
    - targets:
        # ... existing ...
        - '10.0.9.3:9558'   # orangepi-zero3
        - '10.0.9.4:9558'   # orangepi-zero3-backup
```

> **Note:** Orange Pi targets are on the LAN VLAN (`10.0.9.0/24`). Prometheus runs in the k8s VLAN (`10.0.30.0/24`). Verify OPNsense rules allow k8s → LAN on the exporter ports before enabling.

---

### 7. `kubernetes/manifests/base/monitor/kube-prom-stack-all.yaml` — Dashboard (MODIFY)

Add the official Garage Grafana dashboard under `grafana.dashboards`:

```yaml
grafana:
  dashboards:
    extra-dashboards:
      # ... existing dashboards ...
      garage:
        url: https://git.deuxfleurs.fr/Deuxfleurs/garage/raw/branch/main/script/telemetry/grafana-garage-dashboard-prometheus.json
        token: ''
        datasource: Prometheus
```

---

### 8. (Optional) `kubernetes/manifests/base/monitor/garage-alerts.yaml` (NEW)

Create a `PrometheusRule` for Garage-specific alerts:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: garage-alerts
  namespace: monitor
spec:
  groups:
    - name: garage
      interval: 60s
      rules:
        - alert: GarageClusterUnhealthy
          expr: cluster_healthy == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Garage cluster is unhealthy"

        - alert: GarageDiskSpaceLow
          expr: (garage_local_disk_avail / garage_local_disk_total) < 0.1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Garage disk space is low on {{ $labels.instance }}"

        - alert: GarageResyncErrors
          expr: block_resync_errored_blocks > 0
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "Garage has persistent resync errors"

        - alert: GarageHighErrorRate
          expr: rate(api_s3_error_counter{status_code=~"5.."}[5m]) > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Garage S3 API high 5xx error rate"
```

Deploy this into the `monitor` namespace alongside the rest of the monitoring stack. ArgoCD will sync it automatically if placed in `kubernetes/manifests/base/monitor/`.

---

## Deployment Steps

1. **Create the module**
   - Write `nix/modules/services/monitoring.nix`
   - Update `nix/modules/services/default.nix`

2. **Update profiles**
   - Modify `nix/profiles/server.nix`
   - Modify `nix/profiles/sbc.nix`

3. **Update Garage host**
   - Modify `nix/hosts/garage/garage.nix` (admin bind + firewall)

4. **Update Prometheus scrape configs**
   - Modify `kubernetes/manifests/base/monitor/kube-prom-stack-all.yaml`

5. **Add Garage dashboard**
   - Modify `kube-prom-stack-all.yaml`

6. **(Optional) Add Garage alerts**
   - Create `kubernetes/manifests/base/monitor/garage-alerts.yaml`

7. **Deploy NixOS changes**
   ```bash
   # Garage (do first — it has the new metrics endpoint)
   colmena apply --on garage --impure

   # Tail
   colmena apply --on tail --impure

   # Orange Pi hosts
   colmena apply --on orangepi-zero3 --impure
   colmena apply --on orangepi-zero3-backup --impure
   ```

8. **Verify metrics endpoints**
   From any K8s node or host with network access:
   ```bash
   # Garage
   curl http://10.0.20.21:9100/metrics     # node_exporter
   curl http://10.0.20.21:9558/metrics     # systemd_exporter
   curl http://10.0.20.21:9633/metrics     # smartctl_exporter
   curl http://10.0.20.21:3903/metrics     # Garage native

   # Tail
   curl http://10.0.30.79:9100/metrics
   curl http://10.0.30.79:9558/metrics
   curl http://10.0.30.79:9633/metrics

   # Orange Pi
   curl http://10.0.9.3:9100/metrics
   curl http://10.0.9.3:9558/metrics
   ```

9. **Verify Loki log shipping**
   In Grafana Explore, query:
   ```
   {host="garage"}
   {host="tail"}
   {host="orangepi-zero3"}
   ```
   Check that systemd journal logs appear with `unit` labels.

10. **Sync K8s manifests**
    - Let ArgoCD sync `kube-prometheus-stack-all.yaml`
    - Verify targets appear in Prometheus UI: **Status → Targets**
    - Verify Garage dashboard appears in Grafana

---

## Post-Deployment Notes

### Orange Pi Troubleshooting
Orange Pi hosts live on the LAN VLAN (`10.0.9.0/24`). Prometheus runs in the k8s VLAN (`10.0.30.0/24`). If scraping fails:
- Check OPNsense firewall rules for k8s → LAN on ports 9100 and 9558
- Consider adding explicit rules similar to the existing "Allow k8s to access opnsense node exporter" rule in `ansible/inventory/group_vars/opnsense.yml`

### Framework Laptop
Excluded from central monitoring. If local metrics are desired later, the module can be enabled on the Framework with `monitoring.enable = true` and a local Prometheus/Grafana stack, or via tailscale mesh scraping.

### Future Work
- **Centralized NixOS scrape configs:** Consider a `ScrapeConfig` CRD (Prometheus Operator) or a separate file per host group instead of editing `additionalScrapeConfigs` monolithically
- **Metrics retention:** Garage metrics on 3903 are lightweight; no additional storage concerns
- **Alert routing:** Garage alerts can be routed to the same channels as existing Prometheus alerts via Alertmanager

---

## Checklist

- [ ] Create `nix/modules/services/monitoring.nix`
- [ ] Update `nix/modules/services/default.nix`
- [ ] Update `nix/profiles/server.nix`
- [ ] Update `nix/profiles/sbc.nix`
- [ ] Update `nix/hosts/garage/garage.nix` (admin bind + firewall)
- [ ] Update `kube-prom-stack-all.yaml` (scrape configs + dashboard)
- [ ] (Optional) Create `garage-alerts.yaml`
- [ ] Deploy to garage and verify metrics
- [ ] Deploy to tail and verify metrics
- [ ] Deploy to orangepi-zero3 and verify metrics
- [ ] Deploy to orangepi-zero3-backup and verify metrics
- [ ] Verify Loki log shipping from all hosts in Grafana
- [ ] Verify Garage dashboard loads in Grafana
- [ ] (Optional) Verify Orange Pi scraping from Prometheus (may require OPNsense rule changes)
