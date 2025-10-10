# Ceph

## In case you need to destroy ceph, check these:
- https://forum.proxmox.com/threads/removing-ceph-completely.62818/
- https://dannyda.com/2021/04/10/how-to-completely-remove-delete-or-reinstall-ceph-and-its-configuration-from-proxmox-ve-pve/
*A combination of both worked for me*

## To create the ceph csi credentials
```bash
# rbd secret
ceph auth get-or-create client.k8s-rbd
ceph auth caps client.k8s-rbd \
  mon 'allow r' \
  osd 'allow class-read object_prefix rbd_children, allow rwx pool=osd'

# cephfs secret
ceph auth get-or-create client.k8s-cephfs
ceph auth caps client.k8s-cephfs \
  mon 'allow r' \
  mds 'allow *' \
  osd 'allow rwx pool=cephfs_metadata, allow rwx pool=cephfs_data' \
  mgr 'allow *'
```
