# Migration Plan: SeaweedFS → Rook Ceph (External Mode)

## Overview

Migrate from SeaweedFS to Ceph RGW using Rook in external cluster mode with full pool lifecycle management. This enables clean cluster teardown without orphaned data by leveraging Rook's CRD-driven pool management.

## Architecture

### Current State
- **Ceph Cluster**: External bare-metal cluster (mons: 10.0.20.11, 10.0.20.12, 10.0.20.15)
- **RBD CSI**: Standalone Helm chart, pool `osd`, StorageClass `csi-rbd-sc` (default)
- **CephFS CSI**: Standalone Helm chart, filesystem `cephfs`, pool `cephfs_data`
- **SeaweedFS**: Helm chart v4.0.393, S3 on port 8333, 5 buckets, ~3TB on Ceph RBD PVCs
- **Proxmox**: Uses Ceph pools for VM storage (separate from K8s)

### Target State
- **Rook Ceph Operator**: Manages CSI drivers, replaces standalone ceph-csi-* charts
- **External Ceph Connection**: Single set of admin credentials shared by blue/green clusters
- **Pool Lifecycle**: `preservePoolsOnDelete: false` - pools destroyed on cluster spin-down
- **RGW in K8s**: CephObjectStore creates pools, deploys RGW pods inside Talos
- **Zero Orphaned Data**: Rook CRD deletion destroys pools on external Ceph cluster

### Pool Naming (Per-Cluster)

| Pool Name | Purpose | Destroyed on Spin-Down |
|-----------|---------|----------------------|
| `k8s-blue-rbd` / `k8s-green-rbd` | RBD PVCs | Yes |
| `k8s-blue-cephfs-*` / `k8s-green-cephfs-*` | CephFS data/metadata | Yes |
| `rgw-blue-*` / `rgw-green-*` | RGW metadata/data | Yes |
| `osd` / `cephfs` / `cephfs_data` | Legacy (to be removed after migration) | Manual cleanup |

## Phase 0: One-Time Ceph Credentials

**Location**: Run on a bare-metal Ceph monitor node (method/indy/japan)
**Output**: Add to `secrets.enc.json` once, shared by both blue and green clusters
**Scope**: External cluster admin credentials (one-time, not cluster-specific)

### Admin Privileges Approach

To enable Rook to create and delete pools on the external Ceph cluster, we use **admin privileges**. Per Rook docs:

> **Note**: Sharing the admin key with the external cluster is not generally recommended, but is necessary for full pool lifecycle management.

With admin privileges, Rook manages CSI secrets internally — no need to pre-create CSI user secrets. This avoids the blue/green CSI user scoping problem entirely.

### Steps

**1. Extract cluster FSID and monitor endpoints:**

```bash
# Get FSID
ceph fsid
# Example: 25afe9dc-2a59-4135-b1fc-6728b065c2a9

# Get monitor IPs
ceph mon dump
# Note the mon IPs (e.g., 10.0.20.11:3300, 10.0.20.12:3300, 10.0.20.15:3300)
```

**2. Extract the admin keyring:**

```bash
# Get admin keyring from ceph cluster
ceph auth get client.admin

# Example output:
# [client.admin]
#     key = AQBxXXhUAAAAABAAHXXXXXXXXXXXXXXXXXX==
#     caps mds = "allow *"
#     caps mgr = "allow *"
#     caps mon = "allow *"
#     caps osd = "allow *"
```

**3. Generate the mon-secret:**

The `rook-ceph-mon` secret requires a `mon-secret` field. Extract it by running the Rook external cluster script in minimal mode:

```bash
# Download script from Rook release
curl -o /tmp/create-external-cluster-resources.py \
  https://raw.githubusercontent.com/rook/rook/v1.16.3/deploy/examples/external/create-external-cluster-resources.py

# Run with --limit-usage to only generate the minimal mon secret
# (CSI secrets are NOT needed — Rook creates them with admin privileges)
python3 /tmp/create-external-cluster-resources.py \
  --namespace rook-ceph \
  --format bash

# From the output, extract only:
# - ROOK_EXTERNAL_FSID
# - ROOK_EXTERNAL_CEPH_MON_DATA
# - ROOK_EXTERNAL_MONITOR_SECRET (mon-secret)
```

### Secrets to Add to `secrets.enc.json`

Under a new `rook-ceph` namespace key — **only two entries** (the mon secret and the mon-endpoints ConfigMap data). CSI secrets are **not included** because Rook creates and manages them internally with admin privileges.

```json
{
  "rook-ceph": {
    "rook-ceph-mon": {
      "cluster-name": "rook-ceph",
      "fsid": "<ROOK_EXTERNAL_FSID>",
      "admin-secret": "<admin-keyring>",
      "mon-secret": "<ROOK_EXTERNAL_MONITOR_SECRET>",
      "ceph-username": "client.admin",
      "ceph-secret": "<admin-keyring>"
    },
    "rook-ceph-mon-endpoints": {
      "data": "<ROOK_EXTERNAL_CEPH_MON_DATA>",
      "mapping": "{}",
      "maxMonId": "0"
    }
  }
}
```

### Terraform Updates

**File**: `tofu/kubernetes/sops.tf`

The existing `kubernetes_secret.this` loop creates all secrets as `type = "Opaque"`, but `rook-ceph-mon` requires `type = "kubernetes.io/rook"`. Additionally, `rook-ceph-mon-endpoints` is a ConfigMap, not a Secret.

**Option A (Recommended): Add special-type field to secrets.enc.json**

Add a `_type` field to entries that need non-default types:

```json
{
  "rook-ceph": {
    "rook-ceph-mon": {
      "_type": "kubernetes.io/rook",
      "cluster-name": "rook-ceph",
      ...
    },
    "rook-ceph-mon-endpoints": {
      "_type": "kubernetes.io/configmap",
      ...
    }
  }
}
```

Then modify `sops.tf` to:

```hcl
# Separate ConfigMaps from Secrets
locals {
  configmap_map = {
    for k, v in local.secrets_map : k => v
    if lookup(v.data, "_type", "") == "kubernetes.io/configmap"
  }
  secret_map = {
    for k, v in local.secrets_map : k => v
    if lookup(v.data, "_type", "") != "kubernetes.io/configmap"
  }
}

# Handle ConfigMaps
resource "kubernetes_config_map" "this" {
  depends_on = [kubernetes_namespace.this]
  for_each    = local.configmap_map

  metadata {
    name      = replace(each.value.name, "-configmap", "")
    namespace = each.value.namespace
  }

  data = { for k, v in each.value.data : k => v if k != "_type" }
}

# Handle Secrets with proper types
resource "kubernetes_secret" "this" {
  depends_on = [kubernetes_namespace.this]
  for_each   = local.secret_map

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  data = { for k, v in each.value.data : k => v if k != "_type" }
  type = lookup(each.value.data, "_type", "Opaque")
}
```

**Important**: The `rook-ceph-mon` secret with type `kubernetes.io/rook` can only be created after the Rook operator CRDs are installed (Phase 1), since the type is a custom type registered by the operator. Run `tofu apply` for this secret **after** the Rook operator is running.

### Verification

```bash
# After tofu apply (post Phase 1)
kubectl get secrets -n rook-ceph
# NAME                      TYPE                   DATA   AGE
# rook-ceph-mon             kubernetes.io/rook     6      1m

kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph
# NAME                      DATA   AGE
# rook-ceph-mon-endpoints   3      1m

# CSI secrets will be created automatically by Rook operator in Phase 2
kubectl get secrets -n rook-ceph | grep csi
# (empty — will appear after CephCluster CRD is applied)
```

## Phase 1: Rook Ceph Operator

**Manifest**: `kubernetes/manifests/base/rook-ceph/operator-all.yaml`
**Sync Wave**: 0

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rook-ceph-operator
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  destination:
    namespace: rook-ceph
    server: https://kubernetes.default.svc
  project: default
  source:
    chart: rook-ceph
    repoURL: https://charts.rook.io/release
    targetRevision: v1.16.3
    helm:
      valuesObject:
        crds:
          enabled: true
        csi:
          enableRbdDriver: true
          enableCephfsDriver: true
          enableCsiAddons: false
          provisionerReplica: 1
        enableDiscoveryDaemon: false
        monitoring:
          enabled: true
  syncPolicy:
    syncOptions:
      - ApplyOutOfSyncOnly=true
      - CreateNamespace=true
    automated:
      prune: true
      selfHeal: true
```

### Verification

```bash
# Operator running
kubectl get pods -n rook-ceph -l app=rook-ceph-operator
# rook-ceph-operator-xxx   1/1   Running

# CRDs installed
kubectl get crd | grep ceph
# cephblockpools.ceph.rook.io
# cephclusters.ceph.rook.io
# cephfilesystems.ceph.rook.io
# cephobjectstores.ceph.rook.io
# ...

# CSI driver pods running
kubectl get pods -n rook-ceph | grep csi
# csi-rbdplugin-xxx
# csi-cephfsplugin-xxx
```

**Do NOT proceed to Phase 2 until all pods are Running.**

## Phase 2: External CephCluster Connection

**Manifest**: `kubernetes/manifests/base/rook-ceph/cluster-blue.yaml` (and `cluster-green.yaml`)
**Sync Wave**: 1

**Dependency**: Phase 0 secrets must exist, Phase 1 operator must be ready

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rook-ceph-cluster-blue
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  destination:
    namespace: rook-ceph
    server: https://kubernetes.default.svc
  project: default
  source:
    chart: rook-ceph-cluster
    repoURL: https://charts.rook.io/release
    targetRevision: v1.16.3
    helm:
      valuesObject:
        operatorNamespace: rook-ceph
        cephClusterSpec:
          external:
            enable: true
          cephVersion:
            image: quay.io/ceph/ceph:v19.2.3
          crashCollector:
            disable: true
          dataDirHostPath: /var/lib/rook
          healthCheck:
            daemonHealth:
              mon:
                disabled: false
                interval: 45s
          monitoring:
            enabled: true
            externalMgrEndpoints:
              - ip: 10.0.20.11
              - ip: 10.0.20.12
              - ip: 10.0.20.15
            externalMgrPrometheusPort: 9283
        # Empty pools - created in Phase 3 via CRDs
        cephBlockPools: {}
        cephFileSystems: {}
        cephObjectStores: {}
  syncPolicy:
    syncOptions:
      - ApplyOutOfSyncOnly=true
    automated:
      prune: true
      selfHeal: true
```

### Verification

```bash
# CephCluster connected
kubectl get cephcluster -n rook-ceph
# NAME                 DATADIR   HOSTPATH   MONCOUNT   AGE   PHASE       MESSAGE
# rook-ceph-external   /var/lib/rook              3          1m    Connected   Cluster is connected

# Health check
kubectl -n rook-ceph get cephcluster rook-ceph-external -o jsonpath='{.status.ceph.health}'
# HEALTH_OK

# Test connectivity from K8s
kubectl run -n rook-ceph --image=quay.io/ceph/ceph:v19.2.3 ceph-test --restart=Never -- \
  ceph --conf=/etc/ceph/ceph.conf --keyring=/etc/ceph/keyring -s
# Should show Ceph cluster status
kubectl delete pod ceph-test -n rook-ceph
```

**If it fails**: Check secrets exist with correct types, verify Ceph mons are reachable from K8s pods.

**After CephCluster connects**, Rook auto-creates CSI secrets:
```bash
kubectl get secrets -n rook-ceph | grep csi
# rook-csi-rbd-provisioner   Opaque     2      30s
# rook-csi-rbd-node           Opaque     2      30s
# rook-csi-cephfs-provisioner Opaque     2      30s
# rook-csi-cephfs-node        Opaque     2      30s
```

## Phase 3: RBD Pool + StorageClass (Blue)

**Manifest**: `kubernetes/manifests/base/rook-ceph/pool-blue.yaml`
**Sync Wave**: 2

**Note**: Use temporary StorageClass name `csi-rbd-sc-blue` to avoid conflict with existing `csi-rbd-sc`

```yaml
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: k8s-blue-rbd
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  name: k8s-blue-rbd
  replicated:
    size: 3
    requireAllReplicasInDifferentHosts: true
  application: rbd
  preservePoolsOnDelete: false
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-rbd-sc-blue  # Temporary name for testing
  annotations:
    argocd.argoproj.io/sync-wave: "2"
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: k8s-blue-rbd
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
mountOptions:
  - discard
```

### Verification

```bash
# Pool created on external Ceph cluster
kubectl get cephblockpool -n rook-ceph
# NAME            PHASE   TYPE         FAILUREDOMAIN   REPLICATION   AGE
# k8s-blue-rbd    Ready   Replicated   host            3             1m

ceph osd pool ls | grep k8s-blue-rbd
# k8s-blue-rbd

# Test PVC provisioning
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rbd-blue
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: csi-rbd-sc-blue
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-rbd-blue -n default
# NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      AGE
# test-rbd-blue   Bound    pvc-xxx-xxx-xxx-xxx                        1Gi        RWO            csi-rbd-sc-blue   10s

# Clean up
kubectl delete pvc test-rbd-blue -n default
# PVC and underlying RBD image should be deleted
```

## Phase 4: CephFS Pool + StorageClass (Blue)

**Manifest**: `kubernetes/manifests/base/rook-ceph/filesystem-blue.yaml`
**Sync Wave**: 2

```yaml
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: k8s-blue-cephfs
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  name: k8s-blue-cephfs
  metadataPool:
    replicated:
      size: 3
  dataPools:
    - replicated:
        size: 3
      application: cephfs
  preservePoolsOnDelete: false
  preserveFilesystemOnDelete: false
  metadataServer:
    activeCount: 1
    activeStandby: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-cephfs-sc-blue  # Temporary name for testing
  annotations:
    argocd.argoproj.io/sync-wave: "2"
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: k8s-blue-cephfs
  pool: k8s-blue-cephfs-data0
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - recover_session=clean
```

### Verification

```bash
# Filesystem created
kubectl get cephfilesystem -n rook-ceph
# NAME                ACTIVEMDS   AGE
# k8s-blue-cephfs     1           1m

# Pools created on external Ceph
ceph osd pool ls | grep k8s-blue-cephfs
# k8s-blue-cephfs-metadata
# k8s-blue-cephfs-data0

# Test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs-blue
  namespace: default
spec:
  accessModes: [ReadWriteMany]
  storageClassName: csi-cephfs-sc-blue
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-cephfs-blue -n default
# NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          AGE
# test-cephfs-blue  Bound    pvc-xxx-xxx-xxx-xxx                        1Gi        RWX            csi-cephfs-sc-blue    10s

# Clean up
kubectl delete pvc test-cephfs-blue -n default
```

## Phase 5: Ceph RGW ObjectStore (Blue)

**Manifests**: `kubernetes/manifests/base/rook-ceph/objectstore-blue.yaml`, `objectstoreuser-all.yaml`
**Sync Waves**: 3 (ObjectStore), 4 (ObjectStoreUsers)

```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: rgw-blue
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  metadataPool:
    replicated:
      size: 3
  dataPool:
    erasureCoded:
      dataChunks: 2
      codingChunks: 1
  preservePoolsOnDelete: false
  gateway:
    port: 80
    instances: 2
---
# Pre-create S3 users for applications
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: loki
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "4"
spec:
  store: rgw-blue
  displayName: "Loki Log Storage"
---
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: argo-artifacts
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "4"
spec:
  store: rgw-blue
  displayName: "Argo Workflow Artifacts"
---
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: cnpg-backups
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "4"
spec:
  store: rgw-blue
  displayName: "CNPG Database Backups"
```

### Ingress for S3

Add to `kubernetes/manifests/base/rook-ceph/common-all.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rook-ceph-common
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  destination:
    namespace: rook-ceph
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: https://github.com/blake-hamm/bhamm-lab.git
    targetRevision: main
    path: kubernetes/charts/common
    helm:
      valuesObject:
        name: rook-ceph
        ingressRoutes:
          - name: s3
            ingressClass: traefik-external
            routes:
              - match: Host(`s3.bhamm-lab.com`)
                kind: Rule
                middlewares:
                  - name: default-headers
                services:
                  - name: rook-ceph-rgw-rgw-blue
                    scheme: http
                    port: 80
                  # NOTE: No gRPC route needed — Ceph RGW does not support
                  # gRPC S3 (unlike SeaweedFS which had h2c:8333)
```

### Verification

```bash
# ObjectStore ready
kubectl get cephobjectstore -n rook-ceph
# NAME        PHASE   ENDPOINT   PORT   AGE
# rgw-blue    Ready              80     1m

# RGW pods running
kubectl get pods -n rook-ceph -l app=rook-ceph-rgw
# rook-ceph-rgw-rgw-blue-a-xxx   2/2   Running
# rook-ceph-rgw-rgw-blue-b-xxx   2/2   Running

# RGW pools on external Ceph
ceph osd pool ls | grep rgw
# rgw-blue-meta
# rgw-blue-data

# Get S3 credentials for a user
kubectl get secret rook-ceph-object-user-rgw-blue-loki -n rook-ceph -o jsonpath='{.data.AccessKey}' | base64 -d
kubectl get secret rook-ceph-object-user-rgw-blue-loki -n rook-ceph -o jsonpath='{.data.SecretKey}' | base64 -d

# Test S3
kubectl port-forward -n rook-ceph svc/rook-ceph-rgw-rgw-blue 8080:80 &
export AWS_ACCESS_KEY_ID=<AccessKey>
export AWS_SECRET_ACCESS_KEY=<SecretKey>
export AWS_ENDPOINT_URL=http://localhost:8080

aws s3 mb s3://test-bucket
aws s3 cp testfile.txt s3://test-bucket/
aws s3 ls s3://test-bucket/
aws s3 rm s3://test-bucket/testfile.txt
aws s3 rb s3://test-bucket

# Clean up
kill %1  # stop port-forward
```

**Do NOT proceed to Phase 6 until RGW is healthy and S3 operations work.**

## Phase 6: Backup CronWorkflow (Blue)

**Manifest**: `kubernetes/manifests/base/rook-ceph/backup-cronworkflow-blue.yaml`
**Sync Wave**: 25

Simpler than SeaweedFS — no need to scale down statefulsets (RGW is stateless). Direct rclone from Ceph RGW → MinIO → R2.

> **Note on RGW credentials**: `CephObjectStoreUser` creates secrets named `rook-ceph-object-user-{store}-{user}` (e.g., `rook-ceph-object-user-rgw-blue-loki`) with keys `AccessKey` and `SecretKey`. Create a dedicated backup user via CephObjectStoreUser and reference its secret in the workflow.

**Prerequisite**: Create a backup user (add to `objectstoreuser-all.yaml` at sync wave 4):

```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: backup
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "4"
spec:
  store: rgw-blue
  displayName: "Backup Service Account"
```

This creates secret `rook-ceph-object-user-rgw-blue-backup` with `AccessKey` and `SecretKey`.

**Prerequisite**: Add ExternalSecrets for MinIO and R2 credentials (in `kubernetes/manifests/base/rook-ceph/common-all.yaml` at sync wave 5, similar to SeaweedFS pattern):

```yaml
externalSecrets:
  enabled: true
  secrets:
    - secretKey: AWS_ACCESS_KEY_ID
      remoteRef:
        key: /core/k8up
        property: S3_ACCESS_KEY_ID
    - secretKey: AWS_SECRET_ACCESS_KEY
      remoteRef:
        key: /core/k8up
        property: S3_SECRET_ACCESS_KEY
    - secretKey: R2_ACCESS_KEY_ID
      remoteRef:
        key: /external/cloudflare
        property: r2-access-key-id
    - secretKey: R2_SECRET_ACCESS_KEY
      remoteRef:
        key: /external/cloudflare
        property: r2-secret-access-key
    - secretKey: R2_ENDPOINT
      remoteRef:
        key: /external/cloudflare
        property: r2-endpoint
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: rook-ceph-backup-onsite
  namespace: rook-ceph
  annotations:
    argocd.argoproj.io/sync-wave: "25"
spec:
  schedule: "0 1 * * *"
  timezone: America/Denver
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  workflowSpec:
    entrypoint: main
    onExit: exit-handler
    templates:
      - name: main
        steps:
          - - name: backup-to-minio
              template: rclone-sync
              arguments:
                parameters:
                  - name: source-endpoint
                    value: "http://rook-ceph-rgw-rgw-blue.rook-ceph:80"
                  - name: dest-endpoint
                    value: "http://10.0.20.199:9000"
      - name: rclone-sync
        inputs:
          parameters:
            - name: source-endpoint
            - name: dest-endpoint
        container:
          image: rclone/rclone
          env:
            - name: SOURCE_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-object-user-rgw-blue-backup
                  key: AccessKey
            - name: SOURCE_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-object-user-rgw-blue-backup
                  key: SecretKey
            - name: DEST_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-external-secret
                  key: AWS_ACCESS_KEY_ID
            - name: DEST_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-external-secret
                  key: AWS_SECRET_ACCESS_KEY
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -ex
              rclone config create source s3 provider=Other \
                access_key_id $SOURCE_ACCESS_KEY \
                secret_access_key $SOURCE_SECRET_KEY \
                endpoint={{inputs.parameters.source-endpoint}}
              rclone config create dest s3 provider=Minio \
                access_key_id $DEST_ACCESS_KEY \
                secret_access_key $DEST_SECRET_KEY \
                endpoint={{inputs.parameters.dest-endpoint}}

              for bucket in loki argo-artifacts cnpg-backups k8up-backups; do
                rclone sync source:$bucket dest:$bucket \
                  --progress --fast-list --transfers=24 --checkers=48 \
                  --s3-chunk-size=32M --s3-upload-concurrency=24
              done
      - name: exit-handler
        steps:
          - - name: sync-to-r2
              when: "{{workflow.status}} == Succeeded"
              template: rclone-sync-r2
      - name: rclone-sync-r2
        container:
          image: rclone/rclone
          env:
            - name: MINIO_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-external-secret
                  key: AWS_ACCESS_KEY_ID
            - name: MINIO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-external-secret
                  key: AWS_SECRET_ACCESS_KEY
            - name: R2_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-external-secret
                  key: R2_ACCESS_KEY_ID
            - name: R2_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-external-secret
                  key: R2_SECRET_ACCESS_KEY
            - name: R2_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-external-secret
                  key: R2_ENDPOINT
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -ex
              rclone config create onsite s3 provider=Minio \
                access_key_id $MINIO_ACCESS_KEY \
                secret_access_key $MINIO_SECRET_KEY \
                endpoint=http://10.0.20.199:9000
              rclone config create offsite s3 provider=Cloudflare \
                access_key_id $R2_ACCESS_KEY_ID \
                secret_access_key $R2_SECRET_ACCESS_KEY \
                endpoint=$R2_ENDPOINT

              rclone sync onsite: offsite: --progress --fast-list
```

### Verification

```bash
# Trigger manually
argo submit --from cronworkflow/rook-ceph-backup-onsite -n rook-ceph

# Check MinIO console for backed-up buckets
# Check R2 console for synced data
```

## Phase 7: DR Test on Blue

**Goal**: Prove pool lifecycle works — destroy and recreate without orphaned data.

### Step 1: Back up all data

```bash
argo submit --from cronworkflow/rook-ceph-backup-onsite -n rook-ceph
# Wait for completion
```

### Step 2: Nuke Rook resources

```bash
# Delete from newest to oldest (respects dependencies)
kubectl delete cephobjectstore rgw-blue -n rook-ceph
kubectl delete cephfilesystem k8s-blue-cephfs -n rook-ceph
kubectl delete cephblockpool k8s-blue-rbd -n rook-ceph

# Wait for finalizers
kubectl get cephobjectstore -n rook-ceph
kubectl get cephfilesystem -n rook-ceph
kubectl get cephblockpool -n rook-ceph
# All should show "NotFound"
```

### Step 3: Verify pool cleanup on external Ceph

```bash
# On Ceph monitor node
ceph osd pool ls | grep k8s-blue
# (no output - pools destroyed)

ceph osd pool ls | grep rgw-blue
# (no output - pools destroyed)

# Confirm only Proxmox and legacy pools remain
ceph osd pool ls
```

### Step 4: Redeploy via ArgoCD

```bash
# Sync ArgoCD apps
argocd app sync rook-ceph-operator rook-ceph-cluster-blue
argocd app sync -l app.kubernetes.io/part-of=rook-ceph

# Or kubectl apply all manifests
kubectl apply -f kubernetes/manifests/base/rook-ceph/
```

### Step 5: Restore data from MinIO

```bash
# Create reverse rclone job
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: restore-from-minio
  namespace: rook-ceph
spec:
  containers:
  - name: rclone
    image: rclone/rclone
    envFrom:
    - secretRef:
        name: rook-ceph-external-secret
    command: ["/bin/sh", "-c"]
    args:
    - |
      rclone config create source s3 provider=Minio \
        access_key_id $MINIO_ACCESS_KEY \
        secret_access_key $MINIO_SECRET_KEY \
        endpoint=http://10.0.20.199:9000
      rclone config create dest s3 provider=Other \
        access_key_id $RGW_ACCESS_KEY \
        secret_access_key $RGW_SECRET_KEY \
        endpoint=http://rook-ceph-rgw-rgw-blue.rook-ceph:80

      for bucket in loki argo-artifacts cnpg-backups k8up-backups; do
        rclone sync source:$bucket dest:$bucket --progress
      done
  restartPolicy: Never
EOF

kubectl logs -f restore-from-minio -n rook-ceph
kubectl delete pod restore-from-minio -n rook-ceph
```

### Step 6: Verify all data intact

```bash
# List buckets
aws --endpoint http://rook-ceph-rgw-rgw-blue.rook-ceph:80 s3 ls

# Verify bucket contents
aws --endpoint http://rook-ceph-rgw-rgw-blue.rook-ceph:80 s3 ls s3://loki --recursive | head
```

**This DR test proves**: Pools are destroyed on CRD deletion (no orphaned data), Rook recreates them on redeploy, and data is restored from backup.

## Phase 8: Green Cluster Deployment

Deploy the same stack to Green cluster with green-specific pool names:

**Files to create**:
- `cluster-green.yaml` (same chart, no changes needed)
- `pool-green.yaml` (use `k8s-green-rbd`)
- `filesystem-green.yaml` (use `k8s-green-cephfs`)
- `objectstore-green.yaml` (use `rgw-green`)
- `backup-cronworkflow-green.yaml`

**Uses same secrets** from Phase 0 (shared credentials).

### Verification (same as Blue phases)

## Phase 9: Data Migration (SeaweedFS → Ceph RGW)

**Migration strategy**: Data migrates to the **green cluster's RGW** (`rgw-green`). This is intentional — blue is used for DR testing (Phase 7), and green becomes the production target. After migration, a blue-green swap promotes green to production.

> **Important**: Both SeaweedFS and Ceph RGW will be serving data simultaneously during this phase. Applications continue pointing to SeaweedFS until Phase 10 cutover. Do not stop SeaweedFS until the migration is verified.

**One-time migration job**:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: seaweedfs-to-rgw-migration
  namespace: rook-ceph
spec:
  containers:
  - name: rclone
    image: rclone/rclone
    command: ["/bin/sh", "-c"]
    args:
    - |
      set -ex
      # Source: SeaweedFS
      rclone config create swfs s3 provider=Other \
        access_key_id $SWFS_ACCESS_KEY \
        secret_access_key $SWFS_SECRET_KEY \
        endpoint=http://seaweedfs-s3.seaweedfs:8333

      # Destination: Ceph RGW
      rclone config create rgw s3 provider=Other \
        access_key_id $RGW_ACCESS_KEY \
        secret_access_key $RGW_SECRET_KEY \
        endpoint=http://rook-ceph-rgw-rgw-green.rook-ceph:80

      # Migrate all buckets
      for bucket in argo-artifacts loki-data tofu-state cnpg-backups k8up-backups; do
        echo "Migrating bucket: $bucket"
        rclone copy swfs:$bucket rgw:$bucket \
          --progress --transfers=24 --checkers=48 \
          --s3-chunk-size=32M --fast-list
      done

      # Verify
      rclone check swfs: rgw: --one-way
    envFrom:
    - secretRef:
        name: migration-credentials
  restartPolicy: Never
```

### Verification

```bash
# List both sources
rclone ls swfs:
rclone ls rgw:

# Spot-check key files
aws --endpoint http://rook-ceph-rgw-rgw-green.rook-ceph:80 s3 ls s3://loki-data --recursive | head
```

## Phase 10: Cutover & Cleanup

### Step 1: Update Application Endpoints

| Application | Update Location | Old Value | New Value |
|------------|----------------|-----------|-----------|
| Loki | Helm values/config | `seaweedfs-s3.seaweedfs:8333` | `rook-ceph-rgw-rgw-green.rook-ceph:80` |
| Argo Workflows | ConfigMap | SeaweedFS S3 | Ceph RGW S3 |
| CNPG | Backup configuration | SeaweedFS | Ceph RGW |
| K8up | Backup target | SeaweedFS | Ceph RGW |
| Tofu Backend | Backend config | `minio-ceph-api.bhamm-lab.com` | `s3.bhamm-lab.com` |

### Step 2: Rename StorageClasses

In `pool-green.yaml` and `filesystem-green.yaml`:
- Change `csi-rbd-sc-green` → `csi-rbd-sc` (add `is-default-class: "true"`)
- Change `csi-cephfs-sc-green` → `csi-cephfs-sc`

### Step 3: Coexist Standalone CSI During Transition

> **Critical**: Do NOT remove the standalone CSI charts until ALL PVCs using the old StorageClasses (`csi-rbd-sc`, `csi-cephfs-sc`) are migrated or deleted. StorageClass is immutable — existing PVs retain their provisioner (`rbd.csi.ceph.com`) and clusterID (`25afe9dc-...`). Removing the standalone CSI driver while these PVs exist will break expand/mount operations.

**Transition order**:
1. Deploy Rook CSI alongside standalone CSI (both run simultaneously)
2. Create new PVCs on Rook-managed StorageClasses (`csi-rbd-sc`, `csi-cephfs-sc`)
3. Migrate existing workloads: delete old PVC → recreate on new StorageClass → restore data
4. Once ALL PVCs reference the Rook provisioner, remove standalone CSI

**Verify no PVCs reference the old CSI before removal**:
```bash
# Check for PVCs still using old CSI provisioner
kubectl get pv -o json | jq '.items[] | select(.spec.csi.driver == "rbd.csi.ceph.com" or .spec.csi.driver == "cephfs.csi.ceph.com") | .metadata.name'
# Must return empty before proceeding
```

Once verified, delete from `kubernetes/manifests/base/ceph/`:
- `csi-rbd-all.yaml`
- `csi-cephfs-all.yaml`
- `csi-snapshotter-all.yaml`

Also remove the old CSI secrets from `secrets.enc.json` (namespace `ceph`, secrets `csi-rbd-secret` and `csi-cephfs-secret`) after confirming no PV references them.

### Step 3b: Update VolumeSnapshotClass and Snapshot Controller

Keep `csi-snapshot-crds-all.yaml` and `snapshot-controller-all.yaml` (these are driver-agnostic), but update them to deploy to the `rook-ceph` namespace instead of `ceph`.

Update `volume-snapshot-class-all.yaml`:
- **driver**: `rbd.csi.ceph.com` → `rook-ceph.rbd.csi.ceph.com`
- **clusterID**: Change to `rook-ceph` (the Rook namespace, replacing both the old `7b02e4a9-...` and `25afe9dc-...` values)
- **Snapshotter secret**: `csi-rbd-secret` in `ceph` → `rook-csi-rbd-provisioner` in `rook-ceph`

### Step 4: Remove SeaweedFS

Delete entire directory: `kubernetes/manifests/base/seaweedfs/`

This removes:
- `helm-all.yaml`
- `common-all.yaml`
- `pvc-all.yaml`
- `backup-cronworkflow-*.yaml`
- `restore-*.yaml`
- `workflow-rbac-all.yaml`

### Step 5: Update Kill-Switch Workflow

Add pool deletion step in `kubernetes/manifests/automations/pipelines/kill-switch-template.yaml`:

```yaml
- name: delete-rook-crds
  script:
    image: alpine/kubectl
    command: ["/bin/sh", "-c"]
    source: |
      # Delete Rook CRDs to trigger pool deletion on external Ceph
      # Do NOT use --force --grace-period=0 — finalizers must run to clean up external Ceph pools
      kubectl delete cephobjectstore --all -n rook-ceph
      kubectl delete cephfilesystem --all -n rook-ceph
      kubectl delete cephblockpool --all -n rook-ceph
      # Wait for finalizers to complete and resources to be fully deleted
      echo "Waiting for Rook CRDs to be fully deleted..."
      for crd in cephobjectstore cephfilesystem cephblockpool; do
        kubectl wait --for=delete "${crd}" --all -n rook-ceph --timeout=120s || true
      done
      echo "Rook CRDs deleted, external Ceph pools cleaned up."
```

Insert this step **before** `delete-pvcs` in the kill-switch workflow.

### Step 6: Update Branch References

In `kubernetes/manifests/base/core-green.yaml`:
```yaml
source:
  targetRevision: main  # Change from feature/storage-refactor
```

### Step 7: Clean Up Legacy Ceph Pools

After migration verified complete:

```bash
# On Ceph monitor node
# 1. Verify no images in legacy pool
rbd ls osd

# 2. If empty, remove
ceph osd pool rm osd osd --yes-i-really-really-mean-it

# Repeat for any other legacy K8s pools
```

## Rollback Plan

If issues arise:

1. **Revert StorageClasses** in ArgoCD
2. **Scale up SeaweedFS** (if not yet deleted)
3. **Restore from backup** to SeaweedFS if needed
4. **Point applications back** to SeaweedFS S3 endpoint

## Success Criteria

- [ ] Rook operator running with CSI drivers
- [ ] External Ceph cluster connected (HEALTH_OK)
- [ ] RBD PVCs provision via `csi-rbd-sc` (Rook-managed)
- [ ] CephFS PVCs provision via `csi-cephfs-sc` (Rook-managed)
- [ ] RGW serves S3 at `s3.bhamm-lab.com`
- [ ] Data migration complete (all 5 buckets)
- [ ] Backup workflows run successfully (RGW → MinIO → R2)
- [ ] DR test passes (pools destroyed/recreated, data restored)
- [ ] Kill-switch destroys pools on cluster teardown
- [ ] No orphaned data in Ceph pools after kill-switch
- [ ] SeaweedFS and standalone CSI removed
- [ ] All applications using Ceph RGW for S3

## Appendix: Key Rook Resources

### Rook CRDs

| CRD | Purpose | Manages on External Ceph |
|-----|---------|-------------------------|
| CephCluster | External cluster connection | Health monitoring, CSI driver deployment |
| CephBlockPool | RBD pool | Creates/deletes `k8s-*-rbd` pool |
| CephFilesystem | CephFS filesystem | Creates/deletes `k8s-*-cephfs-*` pools |
| CephObjectStore | S3/RGW object store | Creates/deletes `rgw-*` pools, deploys RGW pods |
| CephObjectStoreUser | S3 user | Creates/deletes S3 credentials |
| CephClient | CephX client | Creates/deletes CephX keys |

### Admin Privileges Documentation

Per [Rook External Cluster Admin Privileges](https://rook.io/docs/rook/latest/CRDs/Cluster/external-cluster/advance-external/#admin-privileges):

To give Rook admin privileges on the external Ceph cluster:

1. Extract admin keyring: `ceph auth get client.admin`
2. Update `rook-ceph-mon` secret:
   - `ceph-username`: `client.admin`
   - `ceph-secret`: `<admin-keyring>`
3. Restart Rook operator (automatic via ArgoCD rollouts)

**Note**: Not generally recommended for security, but necessary for full pool lifecycle management.

### Sync Wave Dependencies

```
Phase 0: Manual (secrets.enc.json)
  ↓
Phase 1: Rook Operator (wave 0)
  ↓
Phase 2: CephCluster CRD (wave 1)
  ↓
Phase 3: RBD Pool (wave 2)
Phase 4: CephFS (wave 2)
  ↓
Phase 5: RGW ObjectStore (wave 3)
Phase 6: Backup Workflows (wave 25)
  ↓
Phase 8-10: Green deployment, migration, cleanup
```

### Troubleshooting

**Issue**: CephCluster stuck in "Connecting" state
**Solution**: Verify secrets exist with correct types, check Ceph mon reachability from K8s pods

**Issue**: Pool creation fails
**Solution**: Verify admin keyring in `rook-ceph-mon` secret, check Ceph auth capabilities

**Issue**: CSI driver not provisioning PVCs
**Solution**: Verify Rook operator created CSI secrets (`rook-csi-rbd-provisioner`, `rook-csi-rbd-node`, etc. in namespace `rook-ceph`), check StorageClass provisioner matches CSI driver name, verify admin keyring in `rook-ceph-mon` secret

**Issue**: RGW pods not starting
**Solution**: Check `cephVersion.image` is set in CephCluster, verify resource limits

**Issue**: Pools not deleted on CRD deletion
**Solution**: Check `preservePoolsOnDelete: false` is set, verify finalizers are being processed

## References

- [Rook External Cluster Documentation](https://rook.io/docs/rook/latest/CRDs/Cluster/external-cluster/)
- [Rook Admin Privileges](https://rook.io/docs/rook/latest/CRDs/Cluster/external-cluster/advance-external/#admin-privileges)
- [Rook Helm Charts](https://rook.io/docs/rook/latest/Helm-Charts/helm-charts/)
- [CephBlockPool CRD](https://rook.io/docs/rook/latest/CRDs/Block-Storage/ceph-block-pool-crd/)
- [CephObjectStore CRD](https://rook.io/docs/rook/latest/CRDs/Object-Storage/ceph-object-store-crd/)
- [Rook External Cluster Resources Script](https://github.com/rook/rook/tree/master/deploy/examples/external)
