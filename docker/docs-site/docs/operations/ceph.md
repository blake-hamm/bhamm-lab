# Ceph

## CephFS Client Key for External Hosts

To mount a CephFS subdirectory on an external machine (e.g. the Framework laptop):

```bash
# Create the root directory and subdirectory in CephFS
sudo mkdir -p /mnt/cephfs-root/bhamm/bhamm-sports

# Create a restricted client key scoped to /bhamm
ceph auth get-or-create client.bhamm \
  mon 'allow r' \
  osd 'allow rw pool=cephfs_data' \
  mds 'allow rw path=/bhamm' \
  mgr 'allow r'

# Export keyring for the client
ceph auth get client.bhamm -o /tmp/cephfs_client_keyring
```

See [CephFS Client Mounts](cephfs-client.md) for the client-side NixOS configuration.

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
  osd 'allow class-read object_prefix rbd_children, allow rwx pool=rbd' \
  mgr 'allow *'


# cephfs secret
ceph auth get-or-create client.k8s-cephfs
ceph auth caps client.k8s-cephfs \
  mon 'allow r' \
  mds 'allow *' \
  osd 'allow rwx pool=cephfs_metadata, allow rwx pool=cephfs_data' \
  mgr 'allow *'
```
