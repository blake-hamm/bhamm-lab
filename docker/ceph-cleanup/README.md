# Ceph cleanup
This python script will cleanup ceph orphaned data in the kubernetes pool. AKA: it deletes data that is not in the prod kubernetes cluster as pv or volume snapshots

## Running
```bash
# Create ceph credentials
ceph auth get-or-create client.k8s-cleaner \
  mon 'profile rbd' \
  osd 'profile rbd pool=osd' \
  osd 'profile rbd pool=cephfs_data' \
  mgr 'profile rbd pool=osd' \
  mgr 'profile rbd pool=cephfs_data'

# Build docker image
docker build -t ceph-cleaner docker/ceph-cleanup

# Run script
docker run -it --rm \
  -v ./tofu/proxmox/talos/result/kube-config-green.yaml:/root/.kube/config \
  ceph-cleaner
```