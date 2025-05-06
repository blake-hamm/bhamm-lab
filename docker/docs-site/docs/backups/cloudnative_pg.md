# Cloudnative pg
## WAL archive to minio
I have refactore cnpg backups so that I don't need to deal with volume snapshots when backing up/restoring. Instead, backups are now orchestrated using minio and the WAL archiving pattern.

There are some manual steps involved with restoring backups:
- Ensure data is available in minio tenant under s3://pg-backups/<namespace>-postgresql
- Ensure no data or directory is empty at s3://pg-backups/<namespace>-postgresql-latest (this is the new target backup directory)

Then, all you need to do in the values is enable:
```yaml
postgresql:
  restore:
    enabled: true
```
Everything else will be automagically handled!

## Depreciated:
For postgres, backups are orchestrated with the cloudnative pg operator. This can be configured with the common helm chart. One thing to note: *these backups require a volumesnapshot.* I still need to ensure a 'new' cluster is able to restore a cloudnative pg. Theoritically, these are the steps:
1. Get snapshothandle name from volumesnapshot
```bash
kubectl get volumesnapshotcontent
kubectl describe volumesnapshotcontent <name> # status.snapshotHandle
# Will be something like:
# 0001-0024-7b02e4a9-b740-4d5a-b519-9585725a55fb-0000000000000003-41809123-732c-4a29-b2fc-ab90635fd74d
# Need to remember last uuid: 41809123-732c-4a29-b2fc-ab90635fd74d
```
2.  Create new k3s cluster w/ ceph storage class and csi (see '../deployments/k3s.md')
3. Enable 'protect' on underlying ceph snapshot (enables cloning)
```bash
# On ceph node
sudo rbd ls kubernetes | grep 41809123-732c-4a29-b2fc-ab90635fd74d
# csi-snap-41809123-732c-4a29-b2fc-ab90635fd74d
sudo rbd snap ls kubernetes/csi-snap-41809123-732c-4a29-b2fc-ab90635fd74d
sudo rbd snap protect kubernetes/csi-snap-41809123-732c-4a29-b2fc-ab90635fd74d@csi-snap-41809123-732c-4a29-b2fc-ab90635fd74d
# Confirm with ls
```
- Restore volume snapshot from ceph and deploy cloudnative pg with recovery config (w/ common helm recoverySnapshotHandle)