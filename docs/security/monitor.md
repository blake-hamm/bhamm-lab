# Homelab Monitoring Setup Documentation

This documentation outlines my homelab monitoring. It focuses on ensuring security and reliability by leveraging Prometheus, Grafana, Alertmanager, and Loki as the core components.

## Overview

**Key Components:**

- **Prometheus:** Collects metrics from nodes, containers, and applications.
- **Grafana:** Visualizes data and creates dashboards for real-time monitoring.
- **Alertmanager:** Manages and routes alerts based on defined thresholds.
- **Loki:** Aggregates and indexes logs from your services for detailed analysis.

**Additional Tools:**

- **SNMP Exporter:** To gather metrics from network devices (e.g., switches, access points).
- **Falco:** For runtime security monitoring in container environments.
- **Wazuh/OSQuery:** For host-based intrusion detection and system integrity checks.
- **Blackbox Exporter:** To probe endpoints for availability and latency.


## What to Monitor

### 1. **Network & Website Security**

- **Port 443 Exposure:**
  - **SSL/TLS Health:**
    - Monitor certificate expiration, handshake errors, and TLS version usage.
  - **HTTP Error Rates:**
    - Track 4xx/5xx errors and anomalous access patterns.
  - **Authentication Failures:**
    - Monitor failed login attempts and unusual authentication events.
- **Firewall/IDS Data:**
  - Capture metrics or logs on intrusion attempts, blocked IPs, and anomalous network traffic.

### 2. **Hardware Monitoring**

- **Bare Metal & VM Health:**
  - **CPU, Memory & Disk Metrics:**
    - Use Node Exporter to monitor CPU load, memory usage, disk I/O, temperatures, and SMART data.
  - **Power & Thermal Readings:**
    - Integrate IPMI metrics for temperature and fan speed monitoring.
- **Environmental Sensors:**
  - Monitor ambient temperature and humidity if available.

### 3. **Storage Monitoring**

- **Ceph Cluster:**
  - **Cluster Health:**
    - Monitor OSD and MON status, replication health, and disk errors.
  - **I/O Performance:**
    - Track latency, throughput, and IOPS.
- **MergerFS/SnapRAID:**
  - **File System Integrity:**
    - Monitor parity status, rebuild progress, and error logs.
  - **Disk Usage & Capacity:**
    - Track trends to avoid potential capacity issues.

### 4. **Website Error & Performance Monitoring**

- **Application Logs:**
  - Aggregate web server logs (e.g., Nginx/Apache) using Loki.
  - Query for error patterns, unusual access, or spikes in request failures.
- **Response Times:**
  - Monitor trends to detect slowdowns or timeouts.
- **Security Events:**
  - Track intrusion detection and access anomalies.

---

## Components & Their Roles

### Prometheus
- **Data Collection:**
  Scrape metrics from:
  - **Node Exporter:** For hardware stats.
  - **cAdvisor & kube-state-metrics:** For container and Kubernetes metrics.
  - **Custom Endpoints:** Instrument your web applications to expose metrics (e.g., authentication events, HTTP status codes).
- **Key Query Examples:**
  - CPU Load: `node_cpu_seconds_total`
  - Disk I/O Latency: `rate(node_disk_io_time_seconds_total[5m])`
  - HTTP Error Rate: `sum(rate(http_requests_total{status=~"4..|5.."}[1m]))`

### Grafana
- **Dashboards:**
  - **Infrastructure Dashboard:** Visualize CPU, memory, disk I/O, and network usage.
  - **Security Dashboard:** Display SSL/TLS metrics, firewall events, and authentication logs.
  - **Storage Dashboard:** Track Ceph health, disk utilization, and mergerfs/SnapRAID status.
  - **Website Performance:** Show HTTP error rates, response times, and uptime.
- **Alert Panels:**
  - Create panels that highlight active alerts from Alertmanager and correlate them with log events from Loki.

### Loki
- **Log Aggregation:**
  - Collect logs from web servers, firewalls, and applications.
  - Tag logs with service names, severity, and environment for easier filtering.
- **Security Log Analysis:**
  - Query for keywords such as `failed login`, `unauthorized`, `panic`, and `error`.
  - Correlate log spikes with metric anomalies from Prometheus.

### Alertmanager
- **Alert Routing:**
  - Define thresholds for resource utilization, HTTP error rates, and security events.
  - Configure alerts for high CPU, memory, or disk usage, abnormal network traffic, and unusual authentication failures.
- **Important Alerts:**
  - **High HTTP Error Rate:**
    - When HTTP 4xx/5xx errors exceed a specified threshold.
  - **High CPU/Memory Utilization:**
    - Alert when resource usage consistently exceeds 90%.
  - **Disk I/O Latency Spike:**
    - Trigger alerts for significant increases in disk I/O latency.
  - **Ceph Cluster Degradation:**
    - Alert on any unhealthy OSDs, replication failures, or disk errors.
  - **MergerFS/SnapRAID Issues:**
    - Notify on parity mismatches or rebuild errors.
  - **SSL/TLS Certificate Expiration:**
    - Warn before certificates expire.
  - **Multiple Failed Login Attempts:**
    - Alert on a spike in authentication failures.
  - **Firewall/IDS Intrusion Events:**
    - Alert on detected intrusion attempts or blocked IP events.
  - **Network Anomalies:**
    - Monitor for unexpected spikes in network latency or traffic.
