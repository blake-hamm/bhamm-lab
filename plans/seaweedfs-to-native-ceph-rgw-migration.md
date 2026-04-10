# Migration Plan: SeaweedFS → Native Ceph RGW

## Overview

Migrate from SeaweedFS to Ceph RGW running natively on Proxmox bare-metal nodes. This abandons the Rook Ceph approach — the standalone Ceph CSI drivers remain unchanged for block/file storage, and RGW is deployed via Ansible on the 3 Proxmox nodes, bridged into Kubernetes via a headless Service/Endpoints. S3 buckets use environment-suffixed names for blue/green isolation.

**Migration Status**: `DRAFT` — This plan is not yet implemented.

---

## Architecture

### Current State
- **Ceph Cluster**: External bare-metal cluster on Proxmox (mons: 10.0.20.11, 10.0.20.12, 10.0.20.15)
- **RBD CSI**: Standalone Helm chart, pool `osd`, StorageClass `csi-rbd-sc` (default), namespace `ceph`
- **CephFS CSI**: Standalone Helm chart, filesystem `cephfs`, pool `cephfs_data`, StorageClass `csi-cephfs-sc`
- **SeaweedFS**: Helm chart v4.0.393, S3 on port 8333, 5 buckets (~3TB on Ceph RBD PVCs)
- **VolumeSnapshotClass**: Uses `csi-rbd-secret` in namespace `ceph`, driver `rbd.csi.ceph.com`
- **Proxmox**: Uses Ceph pools for VM storage (separate from K8s)

### Target State
- **Ceph CSI**: Standalone drivers **remain as-is** — no changes to `csi-rbd`, `csi-cephfs`, or their StorageClasses
- **Ceph RGW**: Native daemon on 3 Proxmox nodes (method/indy/japan), port 7480, managed by Ansible
- **K8s Networking**: Headless Service + Endpoints resource bridges RGW into the `storage` namespace
- **S3 Ingress**: Traefik IngressRoute (`s3.bhamm-lab.com`) points to the headless Service
- **Object Storage**: No Rook CRDs, no in-cluster RGW pods — RGW runs outside K8s lifecycle
- **Bucket Naming**: Environment-suffixed (`loki-blue`, `loki-green`, `argo-artifacts-blue`, etc.) except `tofu-state` (shared)
- **Bucket Management**: Argo Workflow template (`s3-bucket-management`) creates/destroys buckets via `aws` CLI
- **S3 Credentials**: Generated via `radosgw-admin` on Proxmox, stored in K8s via SOPS/ExternalSecrets
- **Kill Switch**: Graceful ArgoCD app pruning → graceful PVC deletion → force cleanup for stuck resources → PV verification

### Why Not Rook?

Rook's external mode requires admin keyring access to the external Ceph cluster and doesn't cleanly support:
- Blue/green pool isolation with independent lifecycle per cluster
- Clean teardown without risking the shared external Ceph cluster
- RGW deployment outside the K8s cluster (Rook wants to run RGW pods inside K8s)
- The current standalone CSI setup already works well for block/file

The native RGW approach keeps block/file storage on proven standalone CSI drivers while running RGW where it belongs — on the Proxmox nodes that host the Ceph cluster.

### Bucket Naming (Blue/Green Isolation)

| Bucket Name | Purpose | Shared? |
|-------------|---------|---------|
| `loki-blue` / `loki-green` | Loki log storage | No |
| `argo-artifacts-blue` / `argo-artifacts-green` | Argo Workflow artifacts | No |
| `cnpg-backups-blue` / `cnpg-backups-green` | CNPG database backups | No |
| `k8up-backups-blue` / `k8up-backups-green` | K8up PVC backups | No |
| `tofu-state` | OpenTofu state (workspaces handle isolation) | Yes |

RGW buckets persist across cluster spin-downs because RGW lives outside the K8s lifecycle. The blue/green suffixes prevent bucket collisions.

---

## Prerequisites Checklist

**Before starting Phase 0, ensure:**
- [ ] Blue cluster is stable and running (HEALTH_OK)
- [ ] Recent backup of all SeaweedFS data to MinIO/R2 exists
- [ ] Ansible inventory is up-to-date for all 3 Proxmox nodes
- [ ] Ceph cluster is HEALTH_OK
- [ ] All K8s nodes can reach Proxmox nodes on port 7480 (firewall rules)
- [ ] `secrets.enc.json` SOPS key is available
- [ ] Argo Workflows CLI (`argo`) is installed and configured

---

## Phase 0: Deploy Ceph RGW on Proxmox

**Status**: `NOT STARTED`

**Location**: Ansible — extend `ansible/roles/proxmox/tasks/ceph.yml` with RGW tasks
**Scope**: Deploy `radosgw` daemon on all 3 Proxmox nodes (method, indy, japan)

### 0.1 Update Ansible Variables

Uncomment and update in `ansible/inventory/group_vars/proxmox.yml`:

```yaml
pve_ceph_rgw_enabled: true
pve_ceph_rgw_port: 7480
pve_ceph_rgw_dns: "s3.bhamm-lab.com"
pve_ceph_rgw_admin: true
```

### 0.2 Add RGW Tasks to Ansible

Add to `ansible/roles/proxmox/tasks/ceph.yml`:

```yaml
- name: Install Ceph RGW package
  apt:
    name: ceph-radosgw
    state: present
  when: pve_ceph_rgw_enabled | bool

- name: Deploy Ceph RGW configuration
  template:
    src: ceph-radosgw.conf.j2
    dest: /etc/ceph/ceph.conf.d/rgw.conf
    owner: ceph
    group: ceph
    mode: '0644'
  notify: restart ceph-radosgw
  when: pve_ceph_rgw_enabled | bool

- name: Create Ceph RGW keyring directory
  file:
    path: /var/lib/ceph/radosgw/ceph-rgw.{{ inventory_hostname }}
    state: directory
    owner: ceph
    group: ceph
    mode: '0755'
  when: pve_ceph_rgw_enabled | bool

- name: Ensure ceph-radosgw service is enabled and started
  service:
    name: ceph-radosgw@rgw.{{ inventory_hostname }}
    state: started
    enabled: true
  when: pve_ceph_rgw_enabled | bool
```

**Manual step**: Create the RGW configuration template `ansible/roles/proxmox/templates/ceph-radosgw.conf.j2`

### 0.3 Run Ansible to Deploy RGW

```bash
# From control machine
ansible-playbook ansible/main.yml --tags proxmox --limit proxmox
```

### 0.4 Verification

```bash
# SSH into each Proxmox node and verify RGW is listening
ss -tlnp | grep 7480
# Expected: LISTEN state on 0.0.0.0:7480

# Test S3 endpoint from any Proxmox node (bootstrap admin user not yet created, expect 403 or 404)
curl -s -o /dev/null -w "%{http_code}" http://10.0.20.11:7480
# Expected: 403 Forbidden (or 200 if auto-admin is enabled)

# Verify all 3 nodes respond
for ip in 10.0.20.11 10.0.20.12 10.0.20.15; do
  echo -n "$ip: "
  curl -s -o /dev/null -w "%{http_code}" http://$ip:7480
done
# Expected: All return 403 or 200

# Check RGW service status on all nodes
systemctl status ceph-radosgw@rgw.<hostname>
# Expected: active (running)
```

**🛑 STOP: Do not proceed to Phase 1 until RGW is listening on port 7480 on all 3 nodes.**

---

## Phase 1: Kubernetes Networking Bridge

**Status**: `NOT STARTED`

**Manifest**: `kubernetes/manifests/base/storage/rgw-endpoints-all.yaml`
**Sync Wave**: 7 (after namespace creation)

### 1.1 Create Namespace Manifest

Create `kubernetes/manifests/base/storage/rgw-endpoints-all.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: storage
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  labels:
    pod-security.kubernetes.io/enforce: privileged
---
apiVersion: v1
kind: Service
metadata:
  name: external-rgw
  namespace: storage
  annotations:
    argocd.argoproj.io/sync-wave: "7"
spec:
  clusterIP: None  # Headless — DNS returns all endpoint IPs
  ports:
    - name: s3
      port: 80
      targetPort: 7480
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: external-rgw
  namespace: storage
  annotations:
    argocd.argoproj.io/sync-wave: "7"
subsets:
  - addresses:
      - ip: 10.0.20.11
      - ip: 10.0.20.12
      - ip: 10.0.20.15
    ports:
      - name: s3
        port: 7480
        protocol: TCP
```

### 1.2 Create Storage Common Chart Application

Create `kubernetes/manifests/base/storage/common-all.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: storage-common
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "8"
spec:
  destination:
    namespace: storage
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: https://github.com/blake-hamm/bhamm-lab.git
    targetRevision: main
    path: kubernetes/charts/common
    helm:
      valuesObject:
        name: storage
        externalSecrets:
          enabled: true
          secrets:
            - secretKey: access_key_id
              remoteRef:
                key: /core/ceph-rgw
                property: admin-access-key-id
            - secretKey: secret_access_key
              remoteRef:
                key: /core/ceph-rgw
                property: admin-secret-access-key
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
            - secretKey: AWS_ACCESS_KEY_ID
              remoteRef:
                key: /core/k8up
                property: S3_ACCESS_KEY_ID
            - secretKey: AWS_SECRET_ACCESS_KEY
              remoteRef:
                key: /core/k8up
                property: S3_SECRET_ACCESS_KEY
        ingressRoutes:
          - name: s3
            ingressClass: traefik-external
            routes:
              - match: Host(`s3.bhamm-lab.com`)
                kind: Rule
                middlewares:
                  - name: default-headers
                services:
                  - name: external-rgw
                    scheme: http
                    port: 80
  syncPolicy:
    syncOptions:
      - ApplyOutOfSyncOnly=true
    automated:
      prune: true
      selfHeal: true
```

### 1.3 Sync ArgoCD Applications

```bash
# Sync namespace and endpoints first
argocd app sync storage

# Verify sync succeeds before proceeding
```

### 1.4 Verification

```bash
# Verify namespace exists
kubectl get namespace storage
# Expected: Active

# Verify headless Service
kubectl get svc external-rgw -n storage
# Expected: external-rgw   ClusterIP   None   <none>   80/TCP

# Verify Endpoints
kubectl get endpoints external-rgw -n storage
# Expected:
# NAME           ENDPOINTS                                AGE
# external-rgw   10.0.20.11:7480,10.0.20.12:7480,10.0.20.15:7480

# Test DNS resolution from within K8s
kubectl run -n storage --image=busybox:1.36 test-dns --rm -it --restart=Never -- nslookup external-rgw.storage.svc.cluster.local
# Expected: Should return all 3 IPs

# Verify IngressRoute exists
kubectl get ingressroute -n storage s3
# Expected: s3 route created

# Test external S3 endpoint (will fail auth, but should reach RGW)
curl -s -o /dev/null -w "%{http_code}" https://s3.bhamm-lab.com
# Expected: 403 Forbidden (auth not set up yet, but connectivity works)
```

**🛑 STOP: Do not proceed to Phase 2 until Endpoints show all 3 IPs and external S3 URL is reachable.**

---

## Phase 2: Bootstrap RGW Users and Pools

**Status**: `NOT STARTED`

**Location**: Run on a Ceph monitor node (method, indy, or japan)
**Scope**: Create RGW pools, admin user, and application-specific S3 users

### 2.1 Create RGW Pools (One-Time)

```bash
# SSH to a Ceph monitor node
ssh root@method

# Create the RGW pools
ceph osd pool create .rgw.root 32 replicated
ceph osd pool create default.rgw.control 32 replicated
ceph osd pool create default.rgw.meta 32 replicated
ceph osd pool create default.rgw.log 32 replicated
ceph osd pool create default.rgw.buckets.index 32 replicated
ceph osd pool create default.rgw.buckets.non-ec 32 replicated
ceph osd pool create default.rgw.buckets.data 64 replicated

# Verify pools created
ceph osd pool ls | grep rgw
```

### 2.2 Create Admin S3 User

```bash
# Create admin user for bucket management
radosgw-admin user create --uid=admin --display-name="RGW Admin" --system

# Record the Access Key and Secret Key — these go into SOPS
```

### 2.3 Create Application-Specific S3 Users (Blue Cluster)

```bash
# Create dedicated S3 users per application
radosgw-admin user create --uid=loki-blue --display-name="Loki (Blue)"
radosgw-admin user create --uid=argo-artifacts-blue --display-name="Argo Artifacts (Blue)"
radosgw-admin user create --uid=cnpg-backups-blue --display-name="CNPG Backups (Blue)"
radosgw-admin user create --uid=k8up-backups-blue --display-name="K8up Backups (Blue)"
radosgw-admin user create --uid=backup-blue --display-name="Backup Service (Blue)"

# Create shared user for tofu-state
radosgw-admin user create --uid=tofu --display-name="OpenTofu State"

# Record all Access Key / Secret Key pairs
```

### 2.4 Update SOPS Secrets

Add to `secrets.enc.json` under new `storage` namespace key:

```json
{
  "storage": {
    "storage-external-secret": {
      "access_key_id": "<radosgw-admin-access-key>",
      "secret_access_key": "<radosgw-admin-secret-key>",
      "loki-blue-access-key-id": "<loki-blue-access-key>",
      "loki-blue-secret-access-key": "<loki-blue-secret-key>",
      "argo-artifacts-blue-access-key-id": "<argo-blue-access-key>",
      "argo-artifacts-blue-secret-access-key": "<argo-blue-secret-key>",
      "cnpg-backups-blue-access-key-id": "<cnpg-blue-access-key>",
      "cnpg-backups-blue-secret-access-key": "<cnpg-blue-secret-key>",
      "k8up-backups-blue-access-key-id": "<k8up-blue-access-key>",
      "k8up-backups-blue-secret-access-key": "<k8up-blue-secret-key>",
      "tofu-access-key-id": "<tofu-access-key>",
      "tofu-secret-access-key": "<tofu-secret-access-key>"
    }
  }
}
```

Encrypt and commit the file.

### 2.5 Sync SOPS Secrets to Cluster

```bash
# Re-run tofu/kubernetes to sync the new secrets
cd tofu/kubernetes
tofu apply -target=kubernetes_secret.this
```

### 2.6 Verification

```bash
# Test admin S3 credentials from within K8s
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 ls

# Expected: Empty bucket list or existing buckets

# Create a test bucket
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 mb s3://test-bucket-123

# List buckets to verify
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 ls

# Clean up test bucket
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 rb s3://test-bucket-123 --force
```

**🛑 STOP: Do not proceed to Phase 3 until admin S3 credentials work and test bucket operations succeed.**

---

## Phase 3: S3 Bucket Provisioning

**Status**: `NOT STARTED`

**Scope**: Create environment-suffixed buckets using the existing Argo Workflow template

### 3.1 Update Bucket Management Template (Optional)

The existing `kubernetes/manifests/automations/pipelines/create-or-destroy-bucket-template.yaml` already supports custom endpoints. We can optionally update it to default to RGW, or pass the endpoint as a parameter.

### 3.2 Create Blue Cluster Buckets

```bash
# Create loki-blue bucket
argo submit --from clusterworkflowtemplate/s3-bucket-management \
  -p bucket-name=loki-blue \
  -p endpoint-url=http://external-rgw.storage.svc.cluster.local:80 \
  -p aws-region=us-east-1 \
  -p destroy-and-create=false \
  -p aws-auth-secret=storage-external-secret \
  -p aws-access-key-id=access_key_id \
  -p aws-secret-access-key=secret_access_key

# Create argo-artifacts-blue bucket
argo submit --from clusterworkflowtemplate/s3-bucket-management \
  -p bucket-name=argo-artifacts-blue \
  -p endpoint-url=http://external-rgw.storage.svc.cluster.local:80 \
  -p aws-region=us-east-1 \
  -p destroy-and-create=false \
  -p aws-auth-secret=storage-external-secret \
  -p aws-access-key-id=access_key_id \
  -p aws-secret-access-key=secret_access_key

# Create cnpg-backups-blue bucket
argo submit --from clusterworkflowtemplate/s3-bucket-management \
  -p bucket-name=cnpg-backups-blue \
  -p endpoint-url=http://external-rgw.storage.svc.cluster.local:80 \
  -p aws-region=us-east-1 \
  -p destroy-and-create=false \
  -p aws-auth-secret=storage-external-secret \
  -p aws-access-key-id=access_key_id \
  -p aws-secret-access-key=secret_access_key

# Create k8up-backups-blue bucket
argo submit --from clusterworkflowtemplate/s3-bucket-management \
  -p bucket-name=k8up-backups-blue \
  -p endpoint-url=http://external-rgw.storage.svc.cluster.local:80 \
  -p aws-region=us-east-1 \
  -p destroy-and-create=false \
  -p aws-auth-secret=storage-external-secret \
  -p aws-access-key-id=access_key_id \
  -p aws-secret-access-key=secret_access_key

# Create shared tofu-state bucket
argo submit --from clusterworkflowtemplate/s3-bucket-management \
  -p bucket-name=tofu-state \
  -p endpoint-url=http://external-rgw.storage.svc.cluster.local:80 \
  -p aws-region=us-east-1 \
  -p destroy-and-create=false \
  -p aws-auth-secret=storage-external-secret \
  -p aws-access-key-id=access_key_id \
  -p aws-secret-access-key=secret_access_key
```

### 3.3 Verification

```bash
# List all buckets via admin credentials from within K8s
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 ls

# Expected output:
# 2024-01-15 10:00:00 loki-blue
# 2024-01-15 10:00:00 argo-artifacts-blue
# 2024-01-15 10:00:00 cnpg-backups-blue
# 2024-01-15 10:00:00 k8up-backups-blue
# 2024-01-15 10:00:00 tofu-state
```

**🛑 STOP: Do not proceed to Phase 4 until all 5 buckets are created and visible.**

---

## Phase 4: Backup CronWorkflow (Blue)

**Status**: `NOT STARTED`

**Manifest**: `kubernetes/manifests/base/storage/backup-cronworkflow-blue.yaml`
**Sync Wave**: 25

### 4.1 Create Backup CronWorkflow

Create `kubernetes/manifests/base/storage/backup-cronworkflow-blue.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: ceph-rgw-backup-onsite
  namespace: storage
  annotations:
    argocd.argoproj.io/sync-wave: "25"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
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
                    value: "http://external-rgw.storage.svc.cluster.local:80"
                  - name: dest-endpoint
                    value: "http://10.0.20.199:9000"
                  - name: env-suffix
                    value: "-blue"
      - name: rclone-sync
        inputs:
          parameters:
            - name: source-endpoint
            - name: dest-endpoint
            - name: env-suffix
        container:
          image: rclone/rclone
          env:
            - name: SOURCE_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
                  key: access_key_id
            - name: SOURCE_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
                  key: secret_access_key
            - name: DEST_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
                  key: AWS_ACCESS_KEY_ID
            - name: DEST_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
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
                rclone sync source:${bucket}{{inputs.parameters.env-suffix}} dest:${bucket}{{inputs.parameters.env-suffix}} \
                  --progress --fast-list --transfers=24 --checkers=48 \
                  --s3-chunk-size=32M --s3-upload-concurrency=24
              done
              # Sync shared bucket without suffix
              rclone sync source:tofu-state dest:tofu-state \
                --progress --fast-list --transfers=24 --checkers=48 \
                --s3-chunk-size=32M --s3-upload-concurrency=24
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
                  name: storage-external-secret
                  key: AWS_ACCESS_KEY_ID
            - name: MINIO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
                  key: AWS_SECRET_ACCESS_KEY
            - name: R2_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
                  key: R2_ACCESS_KEY_ID
            - name: R2_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
                  key: R2_SECRET_ACCESS_KEY
            - name: R2_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: storage-external-secret
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

### 4.2 Sync ArgoCD Application

```bash
# Sync the storage application (includes the CronWorkflow)
argocd app sync storage
```

### 4.3 Verification (Manual Trigger)

```bash
# Trigger backup manually
argo submit --from cronworkflow/ceph-rgw-backup-onsite -n storage

# Watch the workflow
argo watch ceph-rgw-backup-onsite-xxxx -n storage

# Verify MinIO after completion
# Open MinIO console at http://10.0.20.199:9000
# Expected buckets with -blue suffix: loki-blue, argo-artifacts-blue, etc.

# Verify R2 after completion (if the workflow succeeds)
# Check Cloudflare R2 console
```

**🛑 STOP: Do not proceed to Phase 5 until backup workflow succeeds and data is visible in MinIO.**

---

## Phase 5: Data Migration (SeaweedFS → Ceph RGW)

**Status**: `NOT STARTED`

**Warning**: Both SeaweedFS and RGW will serve data simultaneously during migration. Applications continue pointing to SeaweedFS until Phase 6 cutover. Do not stop SeaweedFS until migration is verified.

### 5.1 Create Migration Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: seaweedfs-to-rgw-migration
  namespace: storage
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
        endpoint=http://external-rgw.storage.svc.cluster.local:80

      # Migrate buckets to environment-suffixed names
      echo "=== Migrating loki-data → loki-blue ==="
      rclone copy swfs:loki-data rgw:loki-blue \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating argo-artifacts → argo-artifacts-blue ==="
      rclone copy swfs:argo-artifacts rgw:argo-artifacts-blue \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating cnpg-backups → cnpg-backups-blue ==="
      rclone copy swfs:cnpg-backups rgw:cnpg-backups-blue \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating k8up-backups → k8up-backups-blue ==="
      rclone copy swfs:k8up-backups rgw:k8up-backups-blue \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating tofu-state → tofu-state ==="
      rclone copy swfs:tofu-state rgw:tofu-state \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Verification ==="
      for bucket in loki-blue argo-artifacts-blue cnpg-backups-blue k8up-backups-blue tofu-state; do
        echo "Bucket: $bucket"
        rclone size rgw:$bucket
      done
    envFrom:
    - secretRef:
        name: migration-credentials  # Combined secret with both SWFS and RGW creds
  restartPolicy: Never
```

Create the secret:

```bash
# Create combined migration credentials secret
kubectl create secret generic migration-credentials \
  --from-literal=SWFS_ACCESS_KEY=<seaweedfs-access-key> \
  --from-literal=SWFS_SECRET_KEY=<seaweedfs-secret-key> \
  --from-literal=RGW_ACCESS_KEY=<admin-access-key> \
  --from-literal=RGW_SECRET_KEY=<admin-secret-key> \
  -n storage
```

### 5.2 Run Migration

```bash
# Apply the migration pod
kubectl apply -f migration-pod.yaml

# Watch the migration
kubectl logs -f seaweedfs-to-rgw-migration -n storage

# Monitor progress — this could take hours for ~3TB
# Check the final verification output
```

### 5.3 Verification

```bash
# List RGW buckets to confirm all migrated
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 ls

# Spot-check key files in loki-blue
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 ls s3://loki-blue --recursive | head -20

# Verify file counts match
# Compare: rclone ls swfs:loki-data | wc -l
# With:    rclone ls rgw:loki-blue | wc -l
```

**🛑 STOP: Do not proceed to Phase 6 until migration completes and file counts match between SeaweedFS and RGW.**

---

## Phase 6: Cutover & Endpoint Updates

**Status**: `NOT STARTED`

**Warning**: This phase switches production S3 traffic from SeaweedFS to RGW. Perform during a maintenance window if necessary.

### 6.1 Update Application S3 Endpoints

Update the following files to use the new RGW endpoint and suffixed bucket names:

#### Loki
**File**: `kubernetes/manifests/base/monitor/loki-all.yaml`
- **Old**: `endpoint: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `endpoint: http://external-rgw.storage.svc.cluster.local:80`
- **Bucket**: Change from `loki-data` to `loki-blue`
- **Credentials**: Reference `storage-external-secret` with `loki-blue-*` keys

#### Argo Workflows
**File**: `kubernetes/manifests/base/argo/workflows-all.yaml`
- **Old**: `endpoint: "seaweedfs-s3.seaweedfs.svc.cluster.local:8333"`
- **New**: `endpoint: "external-rgw.storage.svc.cluster.local:80"`
- **Bucket**: Change from `argo-artifacts` to `argo-artifacts-blue`
- **Credentials**: Reference `storage-external-secret` with `argo-artifacts-blue-*` keys

#### CNPG (Common Chart Template)
**File**: `kubernetes/charts/common/templates/pg-objectstore.yaml`
- **Old**: `endpointURL: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `endpointURL: http://external-rgw.storage.svc.cluster.local:80`
- **Bucket**: Update to use `-blue` suffix
- **Credentials**: Reference appropriate keys from `storage-external-secret`

#### K8up Schedule (Common Chart Template)
**File**: `kubernetes/charts/common/templates/k8up-schedule.yaml`
- **Old**: `value: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `value: http://external-rgw.storage.svc.cluster.local:80`
- **Bucket**: Update to use `-blue` suffix

#### K8up Restore (Common Chart Template)
**File**: `kubernetes/charts/common/templates/k8up-restore.yaml`
- **Old**: `value: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `value: http://external-rgw.storage.svc.cluster.local:80`
- **Bucket**: Update to use `-blue` suffix

#### MLflow (Green Cluster)
**File**: `kubernetes/manifests/apps/ai/models/helm-green.yaml`
- **Old**: `MLFLOW_S3_ENDPOINT_URL: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `MLFLOW_S3_ENDPOINT_URL: http://external-rgw.storage.svc.cluster.local:80`
- **Bucket**: Update to use `-green` suffix for green cluster

### 6.2 Sync Updated Applications

```bash
# Sync monitor stack (Loki)
argocd app sync monitor

# Sync Argo
argocd app sync argo

# Sync affected apps
argocd app sync ai-models-green  # or whichever includes MLflow
```

### 6.3 Verification

```bash
# Verify Loki can write to new endpoint
# Check Loki logs for S3 errors
kubectl logs -n monitor deployment/loki-distributed-distributor | grep -i s3

# Verify Argo Workflows can write artifacts
# Submit a test workflow and check artifact upload

# Verify CNPG backups work
# Check PostgreSQL cluster backup status
kubectl get backups.postgresql.cnpg.io -A

# Verify external S3 URL still works
curl -s -o /dev/null -w "%{http_code}" https://s3.bhamm-lab.com
# Expected: 403 Forbidden (auth check) or 200 if endpoint accessible
```

**🛑 STOP: Do not proceed to Phase 7 until all applications verify they can read/write to RGW.**

---

## Phase 7: Remove SeaweedFS

**Status**: `NOT STARTED`

**Warning**: Only perform after Phase 6 cutover is verified and applications are stable.

### 7.1 Backup Final SeaweedFS State

```bash
# Trigger one final backup to MinIO/R2
argo submit --from cronworkflow/seaweedfs-offsite-backup -n seaweedfs

# Wait for completion
```

### 7.2 Remove SeaweedFS Manifests

```bash
# Delete entire SeaweedFS directory from git
rm -rf kubernetes/manifests/base/seaweedfs/

# Commit the changes
git commit -m "Remove SeaweedFS — migrated to native Ceph RGW"

# Push to trigger ArgoCD sync
```

### 7.3 ArgoCD Will Remove

ArgoCD will automatically remove:
- `helm-all.yaml` (SeaweedFS Helm chart)
- `common-all.yaml` (IngressRoute, ExternalSecrets)
- `pvc-all.yaml` (PVC for SeaweedFS data)
- `backup-cronworkflow-blue-hack.yaml`
- `backup-cronworkflow-green.yaml`
- `restore-blue-hack.yaml`
- `restore-green.yaml`
- `workflow-rbac-all.yaml`

### 7.4 Verification

```bash
# Verify SeaweedFS namespace is gone
kubectl get namespace seaweedfs
# Expected: Error from server (NotFound): namespaces "seaweedfs" not found

# Verify no SeaweedFS pods running
kubectl get pods --all-namespaces | grep seaweedfs
# Expected: No results

# Verify RGW buckets still accessible
kubectl run -n storage --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never -- \
  --endpoint-url http://external-rgw.storage.svc.cluster.local:80 \
  --access-key <admin-access-key> \
  --secret-key <admin-secret-key> \
  s3 ls
```

**🛑 STOP: Do not proceed to Phase 8 until SeaweedFS is fully removed and all applications continue functioning.**

---

## Phase 8: Green Cluster Setup (When Needed)

**Status**: `NOT STARTED`

When deploying the green cluster, follow the same phases but with `-green` suffixes.

### 8.1 Create Green S3 Users

```bash
# On a Ceph monitor node
radosgw-admin user create --uid=loki-green --display-name="Loki (Green)"
radosgw-admin user create --uid=argo-artifacts-green --display-name="Argo Artifacts (Green)"
radosgw-admin user create --uid=cnpg-backups-green --display-name="CNPG Backups (Green)"
radosgw-admin user create --uid=k8up-backups-green --display-name="K8up Backups (Green)"
radosgw-admin user create --uid=backup-green --display-name="Backup Service (Green)"
```

### 8.2 Update SOPS Secrets

Add green credentials to `secrets.enc.json`:

```json
{
  "storage": {
    "loki-green-access-key-id": "<loki-green-access-key>",
    "loki-green-secret-access-key": "<loki-green-secret-key>",
    "argo-artifacts-green-access-key-id": "<argo-green-access-key>",
    "argo-artifacts-green-secret-access-key": "<argo-green-secret-key>",
    // etc.
  }
}
```

### 8.3 Create Green Buckets

```bash
argo submit --from clusterworkflowtemplate/s3-bucket-management \
  -p bucket-name=loki-green \
  -p endpoint-url=http://external-rgw.storage.svc.cluster.local:80 \
  -p aws-region=us-east-1 \
  -p destroy-and-create=false \
  -p aws-auth-secret=storage-external-secret \
  -p aws-access-key-id=access_key_id \
  -p aws-secret-access-key=secret_access_key

# Repeat for other green buckets
```

### 8.4 Create Green Backup CronWorkflow

Create `kubernetes/manifests/base/storage/backup-cronworkflow-green.yaml`:
- Same as blue but with suffix `-green`
- Sync wave: 25

### 8.5 Deploy Green Cluster Storage

The green cluster will use the same `storage` namespace manifests. CSI drivers connect to the same external Ceph cluster with the same credentials.

---

## Phase 9: Kill-Switch Update

**Status**: `NOT STARTED`

**Manifest**: `kubernetes/manifests/automations/pipelines/kill-switch-template.yaml`

### 9.1 Redesign Kill-Switch Workflow

The kill-switch needs fundamental changes:
- **Remove Rook CRD logic** — no Rook in this architecture
- **Graceful-first approach** — let ArgoCD prune and CSI sidecars clean up
- **Add PV verification** — ensure zero orphaned data

See the updated kill-switch template in Appendix A.

### 9.2 Update and Sync

```bash
# Update the kill-switch template
vim kubernetes/manifests/automations/pipelines/kill-switch-template.yaml

# Commit and push
git add kubernetes/manifests/automations/pipelines/kill-switch-template.yaml
git commit -m "Update kill-switch for native RGW architecture"
git push

# Sync ArgoCD
argocd app sync automations
```

### 9.3 Verification (Test Kill-Switch on Non-Production)

⚠️ **WARNING**: Only test kill-switch on a non-production environment or during a planned teardown.

```bash
# Submit kill-switch workflow
argo submit --from workflowtemplate/kill-switch -n argo

# Watch the workflow
argo watch kill-switch-xxxx -n argo

# After completion, verify on Ceph monitor:
# rbd ls osd  # Should be empty (no orphaned images)
# ceph fs subvolume ls cephfs  # Should be empty (no orphaned subvolumes)
```

---

## Phase 10: Cleanup Legacy Ceph Pools

**Status**: `NOT STARTED`

### 10.1 Verify SeaweedFS RBD Images Are Gone

```bash
# SSH to a Ceph monitor node
ssh root@method

# Check if any RBD images remain in osd pool
rbd ls osd

# If empty or only contains images we still need, proceed to 10.2
```

### 10.2 Remove Legacy Pools (If Safe)

```bash
# Only run if Step 10.1 confirms no needed images exist
ceph osd pool rm osd osd --yes-i-really-really-mean-it

# Review remaining pools
ceph osd pool ls
# Expected: Proxmox pools, RGW pools, and new K8s CSI pools only
```

### 10.3 Verification

```bash
# Final pool state should include:
# - default.rgw.* (RGW system pools)
# - .rgw.root
# - Any Proxmox VM storage pools
# - CephFS pools (cephfs, cephfs_data) if still used
# - Block pool (osd) if kept
```

---

## Rollback Plan

If issues arise during any phase:

1. **Revert S3 endpoints** in application configs back to `seaweedfs-s3.seaweedfs:8333`
2. **Scale up SeaweedFS** (if not yet deleted): restore manifests from git history
3. **Restore from backup** to SeaweedFS if needed (MinIO/R2 copies exist)
4. **Disable RGW** on Proxmox: set `pve_ceph_rgw_enabled: false` and re-run Ansible
5. **Delete RGW buckets** via Argo workflow if needed to start fresh

---

## Success Criteria

**All phases must pass these checks:**

- [ ] **Phase 0**: RGW daemon running on all 3 Proxmox nodes, port 7480 reachable
- [ ] **Phase 1**: Headless Service + Endpoints resolve, external S3 URL reachable
- [ ] **Phase 2**: Admin S3 credentials work, test bucket operations succeed
- [ ] **Phase 3**: All 5 buckets created and visible via `s3 ls`
- [ ] **Phase 4**: Backup CronWorkflow succeeds, data visible in MinIO
- [ ] **Phase 5**: Migration completes, file counts match between SeaweedFS and RGW
- [ ] **Phase 6**: All 6 application endpoint references updated, applications verified
- [ ] **Phase 7**: SeaweedFS removed, applications continue functioning
- [ ] **Phase 8**: Green cluster storage manifests ready (when needed)
- [ ] **Phase 9**: Kill-switch updated and tested, no orphaned data
- [ ] **Phase 10**: Legacy pools reviewed and cleaned up
- [ ] **Final**: CSI drivers (`csi-rbd-sc`, `csi-cephfs-sc`) remain functional, no disruptions

---

## Appendix A: Updated Kill-Switch Workflow

**Status**: `DRAFT`

**File**: `kubernetes/manifests/automations/pipelines/kill-switch-template.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: kill-switch
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "7"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  activeDeadlineSeconds: 600
  templates:
    - name: cleanup
      steps:
        - - name: pause-argocd-apps
            template: pause-apps
        - - name: delete-cnpg-clusters
            template: delete-cnpg-clusters
        - - name: graceful-delete-pvcs
            template: graceful-delete-pvcs
        - - name: delete-argocd-apps
            template: delete-apps
        - - name: force-cleanup-stuck-resources
            template: force-cleanup
        - - name: verify-pvs-gone
            template: verify-pvs-gone
    - name: pause-apps
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          kubectl get applications -n argocd -o name | xargs -I {} kubectl patch {} -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
    - name: delete-cnpg-clusters
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          kubectl delete clusters.postgresql.cnpg.io --all --all-namespaces --wait=true
    - name: graceful-delete-pvcs
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          # Delete all PVCs gracefully — let CSI sidecars handle cleanup
          kubectl delete pvc --all --all-namespaces --timeout=120s
    - name: delete-apps
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          # Properly delete ArgoCD apps to cascade-delete managed resources
          kubectl delete applications --all -n argocd --wait=true --timeout=300s
    - name: force-cleanup
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          # Force cleanup any stuck resources after graceful deletion
          # Remove finalizers from stuck PVCs
          for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
            for pvc in $(kubectl get pvc -n $ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
              kubectl patch pvc $pvc -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
            done
          done
          # Remove finalizers from stuck PVs
          for pv in $(kubectl get pv -o jsonpath='{.items[?(@.status.phase!="Available")].metadata.name}' 2>/dev/null); do
            kubectl patch pv $pv -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
          done
          # Force delete namespaces stuck in Terminating
          for ns in $(kubectl get namespaces -o jsonpath='{.items[?(@.status.phase=="Terminating")].metadata.name}'); do
            kubectl delete namespace $ns --force --grace-period=0 2>/dev/null || true
          done
    - name: verify-pvs-gone
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          # Verify no orphaned PVs remain
          echo "Checking for remaining PVs..."
          remaining_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -v "^NAME" || true)
          if [ -z "$remaining_pvs" ]; then
            echo "SUCCESS: All PVs cleaned up. No orphaned data in Ceph."
          else
            echo "WARNING: Some PVs remain:"
            echo "$remaining_pvs"
            echo "Check Ceph for orphaned RBD images:"
            echo "  rbd ls <pool>"
            echo "  ceph fs subvolume ls cephfs"
            exit 1
          fi
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workflow-admin
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "5"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: workflow-admin-role
  annotations:
    argocd.argoproj.io/sync-wave: "5"
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: workflow-admin-binding
  annotations:
    argocd.argoproj.io/sync-wave: "6"
subjects:
  - kind: ServiceAccount
    name: workflow-admin
    namespace: argo
roleRef:
  kind: ClusterRole
  name: workflow-admin-role
  apiGroup: rbac.authorization.k8s.io
```

**Key Changes from Old Kill-Switch:**
1. **Removed Rook CRD deletion** — not applicable
2. **CNPG deleted with `--wait=true`** — graceful before PVCs
3. **PVCs deleted gracefully first** — allows CSI sidecars to clean up
4. **ArgoCD apps deleted with `--wait=true`** — ensures cascade deletion
5. **Force cleanup as fallback** — only after graceful attempt
6. **PV verification step** — confirms zero orphaned data
7. **RGW buckets persist** on Proxmox — safe from kill-switch

---

## Appendix B: References

### Why Standalone CSI Stays

The standalone Ceph CSI drivers (`csi-rbd` and `csi-cephfs` in namespace `ceph`) connect directly to the external Ceph cluster using `client.admin` credentials with the cluster FSID `25afe9dc-2a59-4135-b1fc-6728b065c2a9`. They handle dynamic PVC provisioning for block and file storage. There is no benefit to replacing them with Rook's CSI — they already work correctly, and replacing them would require migrating all existing PVCs to new StorageClasses with a different provisioner name.

### RGW on Proxmox vs. In-Cluster

**Pros** of running RGW natively on Proxmox:
- RGW survives K8s cluster teardown
- No need for CephObjectStore CRDs
- Simpler networking
- No need to share admin keyring with K8s
- Better suited for blue/green isolation

**Cons**:
- No auto-scaling of RGW instances tied to K8s workloads
- Ansible-managed rather than GitOps-managed

**Acceptable trade-off**: RGW is stateless and low-resource; 3 instances across the Proxmox nodes provides redundancy.

### Bucket Management

The existing `s3-bucket-management` ClusterWorkflowTemplate (`create-or-destroy-bucket-template.yaml`) creates and destroys buckets against any S3-compatible endpoint. Pass `endpoint-url=http://external-rgw.storage.svc.cluster.local:80` as a parameter.

### Sync Wave Dependencies

```
Phase 0: Ansible (RGW on Proxmox — one-time)
  ↓
Phase 1: K8s Service/Endpoints/IngressRoute (wave 7-8)
  ↓
Phase 2: Bootstrap Users and Pools (one-time, then green variant)
  ↓
Phase 3: S3 Bucket Provisioning (Argo Workflow)
  ↓
Phase 4: Backup CronWorkflow (wave 25)
  ↓
Phase 5: Data Migration (SeaweedFS → RGW)
  ↓
Phase 6: Cutover (update endpoints)
  ↓
Phase 7: Remove SeaweedFS
  ↓
Phase 8: Green Cluster Setup (when needed)
  ↓
Phase 9: Kill-switch update
  ↓
Phase 10: Cleanup legacy pools
```

---

## Appendix C: Troubleshooting Guide

### Phase 0 Issues

**Issue**: RGW not responding on port 7480
**Solution**:
- Check `/etc/ceph/ceph.conf.d/rgw.conf` exists
- Verify `ceph-radosgw@rgw.<hostname>` service: `systemctl status ceph-radosgw@rgw.method`
- Check firewall: `ufw allow 7480` or `iptables -L | grep 7480`
- Review RGW logs: `journalctl -u ceph-radosgw@rgw.<hostname>`

**Issue**: Ceph RGW service fails to start
**Solution**:
- Verify Ceph cluster is HEALTH_OK: `ceph -s`
- Check RGW keyring permissions: `ls -la /var/lib/ceph/radosgw/`
- Ensure pools exist: `ceph osd pool ls | grep rgw`

### Phase 1 Issues

**Issue**: Headless Service not resolving
**Solution**:
- Verify Endpoints resource: `kubectl get endpoints external-rgw -n storage`
- Check Service selector (should be `clusterIP: None`): `kubectl get svc external-rgw -n storage -o yaml`
- Test DNS from pod: `kubectl run -it --rm --image=busybox test -- nslookup external-rgw.storage.svc.cluster.local`

**Issue**: External S3 URL not reachable
**Solution**:
- Verify IngressRoute: `kubectl get ingressroute -n storage`
- Check Traefik logs: `kubectl logs -n traefik deployment/traefik`
- Test directly to RGW: `curl http://10.0.20.11:7480` from K8s node

### Phase 2 Issues

**Issue**: S3 credentials rejected
**Solution**:
- Verify user exists: `radosgw-admin user info --uid=admin`
- Check credentials in SOPS: `sops secrets.enc.json`
- Test from Proxmox first: `aws --endpoint-url http://localhost:7480 s3 ls`

### Phase 3 Issues

**Issue**: Bucket creation fails via Argo workflow
**Solution**:
- Check workflow logs: `argo logs <workflow-name> -n storage`
- Verify secret exists: `kubectl get secret storage-external-secret -n storage`
- Test manually from pod: `kubectl run --rm -it --image=amazon/aws-cli test -- /bin/sh`

### Phase 4 Issues

**Issue**: Backup workflow fails
**Solution**:
- Check rclone config in pod
- Verify MinIO endpoint reachable: `curl http://10.0.20.199:9000`
- Check credentials for MinIO and R2
- Review workflow logs for specific bucket errors

### Phase 5 Issues

**Issue**: Migration is slow
**Solution**:
- Adjust rclone flags: increase `--transfers` and `--checkers`
- Consider running migration during low-traffic hours
- Monitor network bandwidth between K8s and Proxmox

**Issue**: Migration verification shows mismatched file counts
**Solution**:
- Re-run specific bucket migration
- Check for files with special characters or permissions issues
- Use `rclone check` for detailed comparison

### Phase 6 Issues

**Issue**: Application can't connect to RGW
**Solution**:
- Verify endpoint URL is correct in config
- Check DNS resolution: `nslookup external-rgw.storage.svc.cluster.local`
- Verify credentials are correctly referenced in secrets
- Check application logs for S3 errors

### Phase 9 Issues

**Issue**: Kill-switch leaves orphaned PVs
**Solution**:
- The `verify-pvs-gone` step will catch this
- Manually check: `kubectl get pv`
- Check Ceph for orphaned data: `rbd ls osd`, `ceph fs subvolume ls cephfs`
- Review CSI driver logs: `kubectl logs -n ceph deployment/ceph-csi-rbd-provisioner`

---

*Document generated for the bhamm-lab infrastructure migration.*
*Last updated: $(date)*
