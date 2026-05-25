# Restic (Framework Laptop)

Restic backs up the Framework laptop to Ceph RGW. These are for the laptop only — cluster PVC backups use k8up (which uses restic internally).

```bash
restic snapshots
restic snapshots --host ollama --host llama-cpp
restic forget bf5265d6
restic prune
```