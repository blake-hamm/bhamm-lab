# Ceph cleanup
This python script will cleanup ceph orphaned data in the kubernetes pool. AKA: it deletes data that is not in the prod kubernetes cluster as pv or volume snapshots

## Running
```bash
# Build docker image
docker build -t ceph-cleaner docker/ceph-cleanup

# Run script
docker run -it --rm \
  -v $HOME/.kube/config-prod:/root/.kube/config \
  ceph-cleaner
```