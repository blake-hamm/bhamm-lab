# Kubernetes backups

## k8up

k8up backs up PVCs directly to Ceph RGW as an S3 target. PVCs must be labeled with `k8up.io/backup: "true"` to be included. Configuration is done through the `common` helm chart — see [deployments/helm](../deployments/helm.md) for details:

```yaml
k8up:
  backup:
    enabled: true
  restore:
    enabled: true
```

The backup target (`AWS_ENDPOINT`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) is configured via External Secrets pulling from Vault at `/core/k8up`.

### Restore Process

1. Ensure Ceph RGW is running and accessible at `http://external-rgw.ceph.svc.cluster.local:80`
2. If RGW needs to be restored first, use the restore workflow: B2 → Garage → RGW (or R2 → Garage → RGW as fallback)
3. k8up restores PVCs from Ceph RGW into the cluster

## Minio [Deprecated]

*Replaced by Garage VM as local backup target. Garage mirrors Ceph RGW buckets via rclone and forwards to Backblaze B2 for offsite.*

Previously, Minio on TrueNAS was used as an intermediate backup target. Backing up Minio's PVC proved insufficient — the config required manual steps. This is no longer relevant as the backup chain is now RGW → Garage → B2.

## Velero [Deprecated]

Originally evaluated for cluster backups but abandoned. GitOps (ArgoCD + Helm) guarantees cluster state restoration; the remaining challenge is PVC data, which k8up handles by backing up to Ceph RGW.
