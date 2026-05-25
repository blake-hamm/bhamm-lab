# CloudNative PG

## WAL Archive to Ceph RGW

Backups are orchestrated using Ceph RGW as the S3-compatible backup target. This is all handled in the cnpg capability in my 'common' helm chart.

```yaml
postgresql:
  enabled: true
  backup:
    enabled: true
    pathVersion: "v1.1" # Optional backup version
  restore:
    enabled: true
    pathVersion: "v1" # Optional new version (bucket path)
```

The `pathVersion` used to be required, but it is now optional. CNPG by default uses the annotation `cnpg.io/skipEmptyWalArchiveCheck: "enabled"`. This means when it creates a cluster from a backup, it replaces the existing backup with the current state. This is desired behavior because we have robust offsite backups of Ceph RGW (Garage mirror + Backblaze B2 offsite).

*Note: Depending on the timing of CNPG backups/WALs and RGW mirror syncs, you may fail to restore Postgres clusters. It's imperative the RGW mirror ran after CNPG backups fully completed.* \
**I highly recommend you only restore in the morning after a weekly RGW-to-B2 backup occurred and no other data was altered.**

## PVC Snapshots [Deprecated]

For Postgres, backups were originally orchestrated with the CloudNative PG operator using volume snapshots. This approach was replaced by WAL archiving to Ceph RGW. The old steps are preserved for reference:

1. Get snapshothandle name from volumesnapshot
```bash
kubectl get volumesnapshotcontent
kubectl describe volumesnapshotcontent <name> # status.snapshotHandle
```
2. Create new cluster with Ceph storage class and CSI
3. Enable 'protect' on underlying Ceph snapshot (enables cloning)
```bash
sudo rbd ls kubernetes | grep <snapshot-uuid>
sudo rbd snap protect kubernetes/<snap-name>@<snap-name>
```
