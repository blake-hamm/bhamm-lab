# Cloudnative pg
## WAL archive to seaweedfs
Backups are now orchestrated using seaweedfs and the WAL archiving pattern. This is all handled in the cnpg capability in my 'common' helm chart. It can be enabled.
```yaml
postgresql:
  enabled: true
  backup:
    enabled: true
    pathVersion: "v1.1" # Optional backup version
  restore:
    enabled: true
    pathVersion: "v1" # Optional new version (swfs bucket path)
```
The `pathVersion` used to be required, but it is now optional. Keep in mind, this is no longer required because cnpg by default uses the annotation `cnpg.io/skipEmptyWalArchiveCheck: "enabled"`. This is 'destructive' in the sense that when it creates a cnpg cluster from a backup, it will then replace the existing backup with the current state. This is desired behavior for me because I have robust backups of swfs (2 copies, 1 offsite). Without the `pathVersion` (which is default) everything else will be automagically handled!

*Note: Depending on the timing of cnpg backups/wals and seaweedfs backups, you may fail to restore postgres clusters. It's imparitive the seaweedfs backup ran after cnpg backups fully completed* \
**I highly recommend you only restore in the morning after a seaweedfs nightly backup occured and no other data was altered.**

## PVC Snapshots [Depreciated]
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