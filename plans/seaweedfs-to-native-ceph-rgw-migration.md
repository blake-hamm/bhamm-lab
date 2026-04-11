# Migration Plan: SeaweedFS → Native Ceph RGW

## Overview

Migrate from SeaweedFS to Ceph RGW running natively on Proxmox bare-metal nodes. This abandons the Rook Ceph approach — the standalone Ceph CSI drivers remain unchanged for block/file storage, and RGW is deployed via Ansible on the 3 Proxmox nodes, bridged into Kubernetes via a ClusterIP Service/EndpointSlice. S3 buckets use plain (non-suffixed) names — the active cluster (blue or green) always writes to the same canonical buckets since clusters never run simultaneously and RGW persists outside the K8s lifecycle.

**Migration Status**: `IN PROGRESS` — Phase 4 complete (S3 buckets provisioned via GitOps using minio/mc), ready for Phase 5 (Application-specific S3 users).

---

## Architecture

### Current State
- **Ceph Cluster**: External bare-metal cluster on Proxmox (mons: 10.0.20.11, 10.0.20.12, 10.0.20.15)
- **RBD CSI**: Standalone Helm chart, pool `osd`, StorageClass `csi-rbd-sc` (default), namespace `ceph`
- **CephFS CSI**: Standalone Helm chart, filesystem `cephfs`, pool `cephfs_data`, StorageClass `csi-cephfs-sc`
- **SeaweedFS**: Helm chart v4.0.393, S3 on port 8333, 8 buckets (~3TB on Ceph RBD PVCs)
- **VolumeSnapshotClass**: Uses `csi-rbd-secret` in namespace `ceph`, driver `rbd.csi.ceph.com`
- **Proxmox**: Uses Ceph pools for VM storage (separate from K8s)
- **Ceph RGW**: Native daemon running on 3 Proxmox nodes (method/indy/japan), port 7480

### Target State
- **Ceph CSI**: Standalone drivers **remain as-is** — no changes to `csi-rbd`, `csi-cephfs`, or their StorageClasses
- **Ceph RGW**: Native daemon on 3 Proxmox nodes (method/indy/japan), port 7480, managed by Ansible
- **K8s Networking**: ClusterIP Service + EndpointSlice bridges RGW into the `ceph` namespace (port 80 → 7480)
- **S3 Ingress**: Traefik IngressRoute (`s3.bhamm-lab.com`) — **deferred until cutover**
- **Object Storage**: No Rook CRDs, no in-cluster RGW pods — RGW runs outside K8s lifecycle
- **Bucket Naming**: Plain names without environment suffixes (`loki-data`, `argo-artifacts`, `cnpg-backups`, `k8up-backups`, `tofu-state`, `mlflow`, `beyond-vibes`, `proxmox-backup-server`) — the active cluster always writes to the same canonical buckets since clusters never run simultaneously
- **Bucket Management**: Argo Workflow template (`s3-bucket-management`) creates/destroys buckets via `minio/mc` client
- **S3 Credentials**: Generated via `radosgw-admin` on Proxmox, stored in K8s via SOPS/ExternalSecrets
- **Kill Switch**: Graceful ArgoCD app pruning → graceful PVC deletion → force cleanup for stuck resources → PV verification

### Why Not Rook?

Rook's external mode requires admin keyring access to the external Ceph cluster and doesn't cleanly support:
- Running RGW outside the K8s cluster (Rook wants to run RGW pods inside K8s)
- Clean teardown without risking the shared external Ceph cluster
- The current standalone CSI setup already works well for block/file

The native RGW approach keeps block/file storage on proven standalone CSI drivers while running RGW where it belongs — on the Proxmox nodes that host the Ceph cluster.

### Bucket Naming (Plain Names — No Environment Suffixes)

All buckets use plain names without environment suffixes. This approach was chosen because:

1. **Blue/green clusters never run simultaneously** — there is no collision risk
2. **Backups only target one cluster** — suffixed backup buckets (e.g., `cnpg-backups-blue`) would be empty or stale when spinning up the alternate cluster, making restore impossible
3. **Simplicity** — environment suffixes double the number of S3 users, secrets, ExternalSecrets, and application configs with no practical benefit
4. **RGW lives outside K8s lifecycle** — buckets persist across cluster spin-downs regardless of naming

| Bucket Name | Purpose | Notes |
|-------------|---------|-------|
| `loki-data` | Loki log storage | Matches current SeaweedFS bucket name |
| `argo-artifacts` | Argo Workflow artifacts | Matches current SeaweedFS bucket name |
| `cnpg-backups` | CNPG database backups | Matches current SeaweedFS bucket name |
| `k8up-backups` | K8up PVC backups | Matches current SeaweedFS bucket name |
| `tofu-state` | OpenTofu state (workspaces handle isolation) | Matches current SeaweedFS bucket name |
| `mlflow` | MLflow artifact storage | Matches current SeaweedFS bucket name |
| `beyond-vibes` | Beyond Vibes app data | New — not in SeaweedFS |
| `proxmox-backup-server` | Proxmox VM backups | New — not in SeaweedFS |

RGW buckets persist across cluster spin-downs because RGW lives outside the K8s lifecycle. The active cluster — whether blue or green — always reads and writes the same canonical buckets.

---

## Prerequisites Checklist

**Before starting Phase 0, ensure:**
- [x] Blue cluster is stable and running (HEALTH_OK)
- [x] Recent backup of all SeaweedFS data to MinIO/R2 exists
- [x] Ansible inventory is up-to-date for all 3 Proxmox nodes
- [x] Ceph cluster is HEALTH_OK
- [x] All K8s nodes can reach Proxmox nodes on port 7480 (firewall rules)
- [x] `secrets.enc.json` SOPS key is available
- [x] Argo Workflows CLI (`argo`) is installed and configured

---

## Phase 0: Deploy Ceph RGW on Proxmox

**Status**: ✅ **COMPLETE**

**Location**: Ansible — `ansible/roles/proxmox/tasks/ceph-rgw.yml`
**Scope**: Deploy `radosgw` daemon on all 3 Proxmox nodes (method, indy, japan)

### 0.1 What Was Done

1. **Added RGW defaults** to `ansible/roles/proxmox/defaults/main.yml`:
   - `pve_ceph_rgw_enabled: false`
   - `pve_ceph_rgw_port: 7480`
   - `pve_ceph_rgw_dns: "s3.bhamm-lab.com"`
   - `pve_ceph_rgw_admin: true`

2. **Enabled RGW** in `ansible/inventory/group_vars/proxmox.yml`:
   - `pve_ceph_rgw_enabled: true`
   - `pve_ceph_rgw_port: 7480`
   - `pve_ceph_rgw_dns: "s3.bhamm-lab.com"`
   - `pve_ceph_rgw_admin: true`

3. **Created** `ansible/roles/proxmox/tasks/ceph-rgw.yml` with the core RGW deployment logic:
   - Installs `radosgw` package
   - Checks if keyring already exists (idempotent via `ceph auth get-or-create`)
   - Uses `ceph auth export` + Jinja2 template to assemble keyring file
   - Copies keyring to `/etc/pve/priv/` via `cp -p` (pmxcfs doesn't support Ansible atomic write)
   - Configures `/etc/pve/ceph.conf` via `community.general.ini_file` with `[client.radosgw.<hostname>]` sections
   - Copies keyring from ClusterFS to local `/etc/ceph/` with `ceph:ceph` ownership
   - Creates systemd symlink for `ceph-radosgw@radosgw.<hostname>.service`
   - Enables and starts the service

4. **Created** `ansible/roles/proxmox/templates/ceph-radosgw.keyring.j2` — Jinja2 template that assembles all exported keys into a single keyring file

5. **Updated** `ansible/roles/proxmox/handlers/main.yml` — Added handler to restart `ceph-radosgw@radosgw.{{ inventory_hostname }}.service`

6. **Updated** `ansible/roles/proxmox/tasks/main.yml` — Added `include_tasks: ceph-rgw.yml` after `lae.proxmox` role

7. **Added RGW pool creation** to `ansible/roles/proxmox/tasks/ceph-rgw.yml` (idempotent, runs once on first node):
   - Checks if `default.rgw.buckets.data` pool exists
   - Creates `default.rgw.buckets.data` and `default.rgw.buckets.non-ec` pools if missing
   - These pools are required for bucket creation to work correctly

8. **Cleaned up unused variables** from defaults and group_vars:
   - Removed `pve_ceph_rgw_port`, `pve_ceph_rgw_dns`, `pve_ceph_rgw_admin`
   - These were dead code — RGW uses default port 7480 and path-style access works without `rgw_dns_name`

### 0.2 Technical Decisions

- **Service naming**: `ceph-radosgw@radosgw.<hostname>` (following neni84 guide convention)
- **Config section**: `[client.radosgw.<hostname>]` (not `[client.rgw.<hostname>]` as in original plan)
- **Shared keyring**: All nodes use a single keyring file at `/etc/ceph/ceph.client.radosgw.keyring`
- **Keyring distribution**: Via Proxmox ClusterFS `/etc/pve/priv/`, then copied locally to `/etc/ceph/`
- **`cp -p` instead of Ansible copy**: Proxmox ClusterFS (`/etc/pve/`) rejects Ansible's atomic write pattern
- **`ceph auth get-or-create`**: More idempotent than separate `ceph-authtool` + `auth add` steps
- **No template for ceph.conf**: Use `community.general.ini_file` to inject sections into `/etc/pve/ceph.conf`
- **RGW pool creation**: Added idempotent pool creation for `default.rgw.buckets.data` and `default.rgw.buckets.non-ec`
- **Removed `rgw_dns_name`**: Path-style access works without it; avoids virtual-hosted-style routing issues

### 0.3 Verification Results

```bash
# All 3 nodes respond on port 7480
for ip in 10.0.20.11 10.0.20.12 10.0.20.15; do
  echo -n "$ip: "
  curl -s -o /dev/null -w "%{http_code}" http://$ip:7480
done
# Result: All return 403 Forbidden (expected, no users yet)

# All 3 services running
systemctl status ceph-radosgw@radosgw.method     # active (running)
systemctl status ceph-radosgw@radosgw.indy       # active (running)
systemctl status ceph-radosgw@radosgw.japan      # active (running)

# Test bucket creation succeeded on method
radosgw-admin user create --uid=test --display-name="Test User"
aws --endpoint-url http://localhost:7480 s3 mb s3://test-bucket
aws --endpoint-url http://localhost:7480 s3 ls
# Result: test-bucket visible
```

**Key files created:**
- `ansible/roles/proxmox/tasks/ceph-rgw.yml`
- `ansible/roles/proxmox/templates/ceph-radosgw.keyring.j2`

---

## Phase 1: Kubernetes Networking Bridge

**Status**: ✅ **COMPLETE**

**Manifest**: `kubernetes/manifests/base/ceph/rgw-endpoints-all.yaml`
**Sync Wave**: 7 (after namespace creation)

### 1.1 Create Namespace and Service Manifest

Create `kubernetes/manifests/base/ceph/rgw-endpoints-all.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-rgw
  namespace: ceph
  annotations:
    argocd.argoproj.io/sync-wave: "7"
spec:
  # clusterIP: auto-assigned (not headless)
  # This allows Cilium to perform DNAT: 80 -> 7480
  ports:
    - name: s3
      port: 80
      targetPort: 7480
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-rgw
  namespace: ceph
  labels:
    kubernetes.io/service-name: external-rgw
  annotations:
    argocd.argoproj.io/sync-wave: "7"
addressType: IPv4
endpoints:
  - addresses:
      - 10.0.20.11
    conditions: {}
  - addresses:
      - 10.0.20.12
    conditions: {}
  - addresses:
      - 10.0.20.15
    conditions: {}
ports:
  - name: s3
    port: 7480
    protocol: TCP
```

### 1.2 Commit and Sync

```bash
# Add the manifest
git add kubernetes/manifests/base/ceph/rgw-endpoints-all.yaml
git commit -m "Add RGW Service and EndpointSlice for internal K8s connectivity"
git push

# Sync via ArgoCD (note: resources were manually created to test, then recreated via ArgoCD)
argocd app sync storage
```

### 1.3 Verification

```bash
# Verify ClusterIP Service (not headless)
kubectl get svc external-rgw -n ceph
# Expected: external-rgw   ClusterIP   10.96.x.x   <none>   80/TCP
# Note: ClusterIP should be auto-assigned, NOT "None"

# Verify EndpointSlice (replaces deprecated v1 Endpoints)
kubectl get endpointslice external-rgw -n ceph
# Expected:
# NAME           ADDRESSTYPE   PORTS   ENDPOINTS                         AGE
# external-rgw   IPv4          7480    10.0.20.11,10.0.20.12,10.0.20.15  5m

# Test connectivity (expect 404 - RGW is reachable, just no route at root path)
kubectl run -n ceph --image=busybox:1.36 test-connect --rm -it --restart=Never -- wget -qO- http://external-rgw.ceph.svc.cluster.local:80 2>&1 | head -5
# Expected: "HTTP/1.1 404 Not Found" (proves port 80 -> 7480 DNAT works)
```

**Key Design Decision**: Initially attempted a headless Service (`clusterIP: None`) with raw Endpoint IPs. This failed because headless Services don't perform port translation — the pod connected directly to `10.0.20.x:80`, but RGW only listens on `:7480`. Switched to **ClusterIP Service** which allows Cilium to perform DNAT from port 80 → 7480, and **EndpointSlice** (replaces deprecated v1 Endpoints) to define the backend RGW IPs.

**🛑 STOP: Do not proceed to Phase 2 until Service shows an auto-assigned ClusterIP and connectivity returns 404 (proving DNAT works).**

---

## Phase 2: Bootstrap RGW Admin User

**Status**: ✅ **COMPLETE**

**Location**: Run on a Ceph monitor node (method, indy, or japan)
**Scope**: Create admin S3 user (prerequisite for testing and bucket operations)

### 2.1 Create Admin S3 User

```bash
# SSH to a Ceph monitor node
ssh root@method

# Create admin user for bucket management
radosgw-admin user create --uid=admin --display-name="RGW Admin" --system

# Record the Access Key and Secret Key — these go into SOPS for Phase 3
```

### 2.2 Test Internal Connectivity from Kubernetes

```bash
# Test S3 list (works with both v1 and v2)
kubectl run --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=<admin-access-key> \
  --env AWS_SECRET_ACCESS_KEY=<admin-secret-key> \
  --env AWS_DEFAULT_REGION=us-east-1 \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3 ls

# Expected: Empty bucket list initially

# Create a test bucket (use s3api to avoid AWS CLI v2 quirk)
kubectl run --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=<admin-access-key> \
  --env AWS_SECRET_ACCESS_KEY=<admin-secret-key> \
  --env AWS_DEFAULT_REGION=us-east-1 \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3api create-bucket --bucket test-bucket-k8s

# Verify bucket exists
kubectl run --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=<admin-access-key> \
  --env AWS_SECRET_ACCESS_KEY=<admin-secret-key> \
  --env AWS_DEFAULT_REGION=us-east-1 \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3 ls

# Clean up test bucket
kubectl run --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=<admin-access-key> \
  --env AWS_SECRET_ACCESS_KEY=<admin-secret-key> \
  --env AWS_DEFAULT_REGION=us-east-1 \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3api delete-bucket --bucket test-bucket-k8s
```

### 2.3 Known Issue: AWS CLI v2 CreateBucket Quirk

**Problem**: AWS CLI v2 (2.34.29) reports `500 Internal Server Error` on `s3 mb` and `s3api create-bucket`, even though:
- RGW logs show HTTP 200 (operation succeeded)
- The bucket IS actually created successfully
- `s3 ls` and `s3api delete-bucket` work fine

**Root Cause**: [Ceph Bug #65794](https://tracker.ceph.com/issues/65794) — RGW returns empty `<Message></Message>` tags in XML responses. AWS CLI v2's botocore library crashes when parsing `None` in `response['Message']`, surfacing as a 500 error to the user even though the operation succeeded server-side.

**Impact**: **Cosmetic only** — all actual S3 operations work correctly:
- Buckets are created despite the 500 error message
- `s3 ls` works (different response format)
- `s3api delete-bucket` works
- Real applications (Loki, Argo, CNPG, K8up) use their own S3 clients which handle RGW responses correctly

**Workaround**: Use `s3api create-bucket` instead of `s3 mb`, or ignore the 500 error and verify with `s3 ls`.

**🟢 READY: Phase 2 is functionally complete. Proceed to Phase 3.**

---

## Phase 3: ExternalSecrets Setup

**Status**: ✅ **COMPLETE**

**Manifest**: `kubernetes/manifests/base/ceph/common-all.yaml`
**Sync Wave**: 8

### 3.1 What Was Done

1. **Rotated admin credentials** — removed compromised `admin` user and created new admin user with fresh access/secret keys

2. **Updated SOPS Secrets** — added to `secrets.enc.json` under `init.ceph.ceph-external-secret`:
   - `access_key_id`: new radosgw-admin-access-key
   - `secret_access_key`: new radosgw-admin-secret-key

3. **Created ExternalSecrets Manifest** — `kubernetes/manifests/base/ceph/common-all.yaml`:
   - ArgoCD Application using sync wave 8
   - ExternalSecret pulls from Vault path `/core/ceph-rgw`
   - Creates secret `ceph-external-secret` in `ceph` namespace

4. **Populated Vault** — added credentials at `secret/core/ceph-rgw` with properties:
   - `admin-access-key-id`
   - `admin-secret-access-key`

5. **Synced and Verified** — secret successfully created:
   ```bash
   kubectl get secret ceph-external-secret -n ceph
   # Result: ceph-external-secret   Opaque   2      30s
   ```

### 3.2 Verification Results

Secret synced with keys:
- `s3_access_key` (20 bytes)
- `s3_secret_key` (40 bytes)
- `s3_user` (5 bytes)

**🟢 READY: Phase 3 is complete. Proceed to Phase 4.**

---

## Phase 4: S3 Bucket Provisioning

**Status**: ✅ **COMPLETE**

**Scope**: Create plain-named buckets via GitOps using Argo Workflow with minio/mc client

**Manifest**: `kubernetes/manifests/base/ceph/buckets-green.yaml`
**Template**: `kubernetes/manifests/automations/pipelines/create-or-destroy-bucket-template.yaml`
**Sync Wave**: 9

### 4.1 Implementation Changes

#### 4.1.1 Tool Selection: minio/mc vs AWS CLI

**Problem**: AWS CLI v2 has a known bug ([Ceph Bug #65794](https://tracker.ceph.com/issues/65794)) with Ceph RGW where empty `<Message></Message>` tags in XML responses cause botocore to crash. Additionally, AWS CLI v1 is no longer published as a Docker image.

**Solution**: Switched to **minio/mc** — a Go-based S3 client that:
- Avoids the AWS CLI v2 bug completely
- Has excellent Ceph RGW compatibility
- Is actively maintained with official Docker images
- Supports all bucket operations (`mc mb`, `mc rb`, `mc ls`, etc.)

**Image**: `minio/mc:RELEASE.2025-08-13T08-35-41Z`

#### 4.1.2 Template Refactoring

The `s3-bucket-management` ClusterWorkflowTemplate was refactored to:
- Accept a JSON array of bucket names (`bucket-names` parameter) instead of single bucket name
- Use `withParam` to fan out bucket creation in parallel
- Reduce code duplication — parameters defined once, not repeated per bucket

**Template Interface**:
```yaml
parameters:
  - name: bucket-names  # JSON array: '["tofu-state","loki-data",...]'
  - name: endpoint-url
  - name: aws-region
  - name: destroy-and-create  # if "true", destroys then recreates
  - name: aws-auth-secret     # secret name in workflow namespace
  - name: aws-access-key-id   # key in secret for access key
  - name: aws-secret-access-key  # key in secret for secret key
```

#### 4.1.3 GitOps Workflow Manifest

**File**: `kubernetes/manifests/base/ceph/buckets-green.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: create-ceph-buckets  # Note: static name, not generateName
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "9"
spec:
  serviceAccountName: argo-workflow
  entrypoint: main
  templates:
    - name: main
      steps:
        - - name: create-buckets
            templateRef:
              name: s3-bucket-management
              template: bucket-management
              clusterScope: true
            arguments:
              parameters:
                - name: bucket-names
                  value: '["tofu-state","loki-data","argo-artifacts","cnpg-backups","k8up-backups","beyond-vibes","mlflow","proxmox-backup-server"]'
                - name: endpoint-url
                  value: http://external-rgw.ceph.svc.cluster.local:80
                - name: aws-region
                  value: us-east-1
                - name: destroy-and-create
                  value: "true"
                - name: aws-auth-secret
                  value: argo-external-secret  # In argo namespace, not ceph
                - name: aws-access-key-id
                  value: s3_access_key
                - name: aws-secret-access-key
                  value: s3_secret_key
```

### 4.2 Hiccups & Lessons Learned

#### Hiccup 1: ArgoCD + generateName

**Problem**: Cannot use `generateName` with ArgoCD because it uses `kubectl apply`, which doesn't support generateName.

**Error**: `cannot use generate name with apply`

**Solution**: Use static `name` instead:
```yaml
metadata:
  name: create-ceph-buckets  # Static name
  # generateName: create-ceph-buckets-  # Don't use this
```

#### Hiccup 2: Secret Namespace Scoping

**Problem**: Workflow pods run in the `argo` namespace, but the secret `ceph-external-secret` was in the `ceph` namespace. Kubernetes secrets are namespace-scoped — `secretKeyRef` can only access secrets in the same namespace as the pod.

**Error**: `Error: secret "ceph-external-secret" not found` (from argo namespace)

**Solution**:
1. Added RGW credentials to `argo/common-all.yaml` ExternalSecret:
   ```yaml
   - secretKey: s3_access_key
     remoteRef:
       key: /core/ceph
       property: s3_access_key
   - secretKey: s3_secret_key
     remoteRef:
       key: /core/ceph
       property: s3_secret_key
   ```
2. Referenced `argo-external-secret` in the workflow instead of `ceph-external-secret`

### 4.3 Verification

```bash
# List all buckets via admin credentials from within K8s
kubectl run -n ceph --image=minio/mc:RELEASE.2025-08-13T08-35-41Z test-s3 --rm -it --restart=Never \
  --env ACCESS_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_access_key}' | base64 -d) \
  --env SECRET_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_secret_key}' | base64 -d) \
  -- /bin/sh -c 'mc alias set ceph http://external-rgw.ceph.svc.cluster.local:80 $ACCESS_KEY $SECRET_KEY && mc ls ceph'

# Expected output (8 buckets):
# [2026-04-10 10:00:00 UTC]     0B tofu-state/
# [2026-04-10 10:00:00 UTC]     0B loki-data/
# [2026-04-10 10:00:00 UTC]     0B argo-artifacts/
# [2026-04-10 10:00:00 UTC]     0B cnpg-backups/
# [2026-04-10 10:00:00 UTC]     0B k8up-backups/
# [2026-04-10 10:00:00 UTC]     0B beyond-vibes/
# [2026-04-10 10:00:00 UTC]     0B mlflow/
# [2026-04-10 10:00:00 UTC]     0B proxmox-backup-server/
```

**🟢 READY: Phase 4 is complete. Proceed to Phase 5.**

---

## Phase 5: Create Application-Specific S3 Users

**Status**: `NOT STARTED`

**Location**: Run on a Ceph monitor node (method, indy, or japan)
**Scope**: Create dedicated S3 users per application and update SOPS

### 5.1 Create Application S3 Users

Each application gets its own S3 user with access to its corresponding bucket. Since clusters never run simultaneously, both clusters share the same users and buckets.

```bash
# SSH to a Ceph monitor node
ssh root@method

# Create dedicated S3 users per application
radosgw-admin user create --uid=loki --display-name="Loki"
radosgw-admin user create --uid=argo-artifacts --display-name="Argo Workflows"
radosgw-admin user create --uid=cnpg-backups --display-name="CNPG Backups"
radosgw-admin user create --uid=k8up-backups --display-name="K8up Backups"
radosgw-admin user create --uid=mlflow --display-name="MLflow"
radosgw-admin user create --uid=tofu --display-name="OpenTofu State"
radosgw-admin user create --uid=proxmox-backup --display-name="Proxmox Backup Server"

# Record all Access Key / Secret Key pairs
```

Optionally, set per-user bucket permissions to restrict each user to only their bucket:

```bash
# Example: restrict loki user to loki-data bucket only
radosgw-admin policy put --uid=loki --bucket=loki-data --policy-file=loki-policy.json
```

### 5.2 Update SOPS Secrets with Application Credentials

Add to `secrets.enc.json` under the `ceph` namespace key:

```json
{
  "ceph": {
    "ceph-external-secret": {
      "access_key_id": "<radosgw-admin-access-key>",
      "secret_access_key": "<radosgw-admin-secret-key>",
      "loki-access-key-id": "<loki-access-key>",
      "loki-secret-access-key": "<loki-secret-key>",
      "argo-artifacts-access-key-id": "<argo-access-key>",
      "argo-artifacts-secret-access-key": "<argo-secret-key>",
      "cnpg-backups-access-key-id": "<cnpg-access-key>",
      "cnpg-backups-secret-access-key": "<cnpg-secret-key>",
      "k8up-backups-access-key-id": "<k8up-access-key>",
      "k8up-backups-secret-access-key": "<k8up-secret-key>",
      "mlflow-access-key-id": "<mlflow-access-key>",
      "mlflow-secret-access-key": "<mlflow-secret-key>",
      "tofu-access-key-id": "<tofu-access-key>",
      "tofu-secret-access-key": "<tofu-secret-key>",
      "proxmox-backup-access-key-id": "<proxmox-access-key>",
      "proxmox-backup-secret-access-key": "<proxmox-secret-key>",
      "R2_ACCESS_KEY_ID": "<r2-access-key-id>",
      "R2_SECRET_ACCESS_KEY": "<r2-secret-access-key>",
      "R2_ENDPOINT": "<r2-endpoint>",
      "AWS_ACCESS_KEY_ID": "<minio-access-key-id>",
      "AWS_SECRET_ACCESS_KEY": "<minio-secret-access-key>"
    }
  }
}
```

Encrypt and commit the file.

### 5.3 Update ExternalSecrets Manifest

Update `kubernetes/manifests/base/storage/common-all.yaml` to include all application credentials:

```yaml
# Add these to the externalSecrets.secrets list:
- secretKey: loki-access-key-id
  remoteRef:
    key: /core/ceph-rgw
    property: loki-access-key-id
- secretKey: loki-secret-access-key
  remoteRef:
    key: /core/ceph-rgw
    property: loki-secret-access-key
- secretKey: argo-artifacts-access-key-id
  remoteRef:
    key: /core/ceph-rgw
    property: argo-artifacts-access-key-id
- secretKey: argo-artifacts-secret-access-key
  remoteRef:
    key: /core/ceph-rgw
    property: argo-artifacts-secret-access-key
# ... repeat for all application credentials
```

### 5.4 Sync Updated Secrets

```bash
# Sync via ArgoCD
argocd app sync storage

# Verify secret contains all keys
kubectl get secret ceph-external-secret -n ceph -o yaml
```

**🛑 STOP: Do not proceed to Phase 6 until all application credentials are in the secret.**

---

## Phase 6: Backup CronWorkflow

**Status**: `NOT STARTED`

**Manifest**: `kubernetes/manifests/base/storage/backup-cronworkflow.yaml`
**Sync Wave**: 25

### 6.1 Create Backup CronWorkflow

Create `kubernetes/manifests/base/storage/backup-cronworkflow.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: ceph-rgw-backup-onsite
  namespace: ceph
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
                    value: "http://external-rgw.ceph.svc.cluster.local:80"
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
                  name: ceph-external-secret
                  key: access_key_id
            - name: SOURCE_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: ceph-external-secret
                  key: secret_access_key
            - name: DEST_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: ceph-external-secret
                  key: AWS_ACCESS_KEY_ID
            - name: DEST_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: ceph-external-secret
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

              for bucket in loki-data argo-artifacts cnpg-backups k8up-backups mlflow beyond-vibes proxmox-backup-server tofu-state; do
                rclone sync source:${bucket} dest:${bucket} \
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
                  name: ceph-external-secret
                  key: AWS_ACCESS_KEY_ID
            - name: MINIO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: ceph-external-secret
                  key: AWS_SECRET_ACCESS_KEY
            - name: R2_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: ceph-external-secret
                  key: R2_ACCESS_KEY_ID
            - name: R2_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: ceph-external-secret
                  key: R2_SECRET_ACCESS_KEY
            - name: R2_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: ceph-external-secret
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

### 6.2 Sync and Test

```bash
# Sync the storage application (includes the CronWorkflow)
argocd app sync storage

# Trigger backup manually for testing
argo submit --from cronworkflow/ceph-rgw-backup-onsite -n ceph

# Watch the workflow
argo watch ceph-rgw-backup-onsite-xxxx -n ceph

# Verify MinIO after completion
# Open MinIO console at http://10.0.20.199:9000
# Expected buckets (matching RGW bucket names): loki-data, argo-artifacts, cnpg-backups, k8up-backups, mlflow, beyond-vibes, proxmox-backup-server, tofu-state
```

**🛑 STOP: Do not proceed to Phase 7 until backup workflow succeeds and data is visible in MinIO.**

---

## Phase 7: Data Migration (SeaweedFS → Ceph RGW)

**Status**: `NOT STARTED`

**Warning**: Both SeaweedFS and RGW will serve data simultaneously during migration. Applications continue pointing to SeaweedFS until Phase 8 cutover. Do not stop SeaweedFS until migration is verified.

### 7.1 Create Migration Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: seaweedfs-to-rgw-migration
  namespace: ceph
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
        endpoint=http://external-rgw.ceph.svc.cluster.local:80

      # Migrate buckets to RGW (1:1 name mapping, no renaming)
      echo "=== Migrating loki-data → loki-data ==="
      rclone copy swfs:loki-data rgw:loki-data \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating argo-artifacts → argo-artifacts ==="
      rclone copy swfs:argo-artifacts rgw:argo-artifacts \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating cnpg-backups → cnpg-backups ==="
      rclone copy swfs:cnpg-backups rgw:cnpg-backups \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating k8up-backups → k8up-backups ==="
      rclone copy swfs:k8up-backups rgw:k8up-backups \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Migrating tofu-state → tofu-state ==="
      rclone copy swfs:tofu-state rgw:tofu-state \
        --progress --transfers=24 --checkers=48 \
        --s3-chunk-size=32M --fast-list

      echo "=== Verification ==="
      for bucket in loki-data argo-artifacts cnpg-backups k8up-backups tofu-state; do
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
  -n ceph
```

### 7.2 Run Migration

```bash
# Apply the migration pod
kubectl apply -f migration-pod.yaml

# Watch the migration
kubectl logs -f seaweedfs-to-rgw-migration -n ceph

# Monitor progress — this could take hours for ~3TB
# Check the final verification output
```

### 7.3 Verification

```bash
# List RGW buckets to confirm all migrated
kubectl run -n ceph --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.access_key_id}' | base64 -d) \
  --env AWS_SECRET_ACCESS_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.secret_access_key}' | base64 -d) \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3 ls

# Spot-check key files in loki-data
kubectl run -n ceph --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.access_key_id}' | base64 -d) \
  --env AWS_SECRET_ACCESS_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.secret_access_key}' | base64 -d) \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3 ls s3://loki-data --recursive | head -20

# Verify file counts match
# Compare: rclone ls swfs:loki-data | wc -l
# With:    rclone ls rgw:loki-data | wc -l
```

**🛑 STOP: Do not proceed to Phase 8 until migration completes and file counts match between SeaweedFS and RGW.**

---

## Phase 8: Cutover, Ingress Setup & Endpoint Updates

**Status**: `NOT STARTED`

**Warning**: This phase switches production S3 traffic from SeaweedFS to RGW and enables external access. Perform during a maintenance window if necessary.

### 8.1 Update Storage Common Chart with IngressRoute

Update `kubernetes/manifests/base/storage/common-all.yaml` to include the IngressRoute:

```yaml
# Add to the helm.valuesObject:
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
```

### 8.2 Sync IngressRoute

```bash
# Sync via ArgoCD
argocd app sync storage

# Verify IngressRoute exists
kubectl get ingressroute -n ceph s3
# Expected: s3 route created

# Test external S3 endpoint
 curl -s -o /dev/null -w "%{http_code}" https://s3.bhamm-lab.com
# Expected: 403 Forbidden (auth check) or 200 if endpoint accessible
```

### 8.3 Update Application S3 Endpoints

Update the following files to use the new RGW endpoint. Bucket names remain unchanged — only the endpoint changes.

#### Loki
**File**: `kubernetes/manifests/base/monitor/loki-all.yaml`
- **Old**: `endpoint: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `endpoint: http://external-rgw.ceph.svc.cluster.local:80`
- **Bucket**: No change — stays `loki-data`
- **Credentials**: Reference `ceph-external-secret` with `loki-*` keys

#### Argo Workflows
**File**: `kubernetes/manifests/base/argo/workflows-all.yaml`
- **Old**: `endpoint: "seaweedfs-s3.seaweedfs.svc.cluster.local:8333"`
- **New**: `endpoint: "external-rgw.ceph.svc.cluster.local:80"`
- **Bucket**: No change — stays `argo-artifacts`
- **Credentials**: Reference `ceph-external-secret` with `argo-artifacts-*` keys

#### CNPG (Common Chart Template)
**File**: `kubernetes/charts/common/templates/pg-objectstore.yaml`
- **Old**: `endpointURL: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `endpointURL: http://external-rgw.ceph.svc.cluster.local:80`
- **Bucket**: No change — stays `cnpg-backups`
- **Credentials**: Reference appropriate keys from `ceph-external-secret`

#### K8up Schedule (Common Chart Template)
**File**: `kubernetes/charts/common/templates/k8up-schedule.yaml`
- **Old**: `value: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `value: http://external-rgw.ceph.svc.cluster.local:80`
- **Bucket**: No change — stays `k8up-backups`

#### K8up Restore (Common Chart Template)
**File**: `kubernetes/charts/common/templates/k8up-restore.yaml`
- **Old**: `value: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `value: http://external-rgw.ceph.svc.cluster.local:80`
- **Bucket**: No change — stays `k8up-backups`

#### MLflow
**File**: `kubernetes/manifests/apps/ai/models/helm-green.yaml`
- **Old**: `MLFLOW_S3_ENDPOINT_URL: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `MLFLOW_S3_ENDPOINT_URL: http://external-rgw.ceph.svc.cluster.local:80`
- **Bucket**: No change — stays `mlflow`

### 8.4 Sync Updated Applications

```bash
# Sync monitor stack (Loki)
argocd app sync monitor

# Sync Argo
argocd app sync argo

# Sync affected apps
argocd app sync ai-models-green  # or whichever includes MLflow
```

### 8.5 Verification

```bash
# Verify Loki can write to new endpoint
# Check Loki logs for S3 errors
kubectl logs -n monitor deployment/loki-distributed-distributor | grep -i s3

# Verify Argo Workflows can write artifacts
# Submit a test workflow and check artifact upload

# Verify CNPG backups work
# Check PostgreSQL cluster backup status
kubectl get backups.postgresql.cnpg.io -A

# Verify external S3 URL works
curl -s -o /dev/null -w "%{http_code}" https://s3.bhamm-lab.com
# Expected: 403 Forbidden (auth check) or 200 if endpoint accessible
```

**🛑 STOP: Do not proceed to Phase 9 until all applications verify they can read/write to RGW.**

---

## Phase 9: Remove SeaweedFS

**Status**: `NOT STARTED`

**Warning**: Only perform after Phase 8 cutover is verified and applications are stable.

### 9.1 Backup Final SeaweedFS State

```bash
# Trigger one final backup to MinIO/R2
argo submit --from cronworkflow/seaweedfs-offsite-backup -n seaweedfs

# Wait for completion
```

### 9.2 Remove SeaweedFS Manifests

```bash
# Delete entire SeaweedFS directory from git
rm -rf kubernetes/manifests/base/seaweedfs/

# Commit the changes
git commit -m "Remove SeaweedFS — migrated to native Ceph RGW"

# Push to trigger ArgoCD sync
```

### 9.3 ArgoCD Will Remove

ArgoCD will automatically remove:
- `helm-all.yaml` (SeaweedFS Helm chart)
- `common-all.yaml` (IngressRoute, ExternalSecrets)
- `pvc-all.yaml` (PVC for SeaweedFS data)
- `backup-cronworkflow-blue-hack.yaml`
- `backup-cronworkflow-green.yaml`
- `restore-blue-hack.yaml`
- `restore-green.yaml`
- `workflow-rbac-all.yaml`

### 9.4 Verification

```bash
# Verify SeaweedFS namespace is gone
kubectl get namespace seaweedfs
# Expected: Error from server (NotFound): namespaces "seaweedfs" not found

# Verify no SeaweedFS pods running
kubectl get pods --all-namespaces | grep seaweedfs
# Expected: No results

# Verify RGW buckets still accessible
kubectl run -n ceph --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.access_key_id}' | base64 -d) \
  --env AWS_SECRET_ACCESS_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.secret_access_key}' | base64 -d) \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3 ls
```

**🛑 STOP: Do not proceed to Phase 10 until SeaweedFS is fully removed and all applications continue functioning.**

---

## Phase 10: Green Cluster Setup (When Needed)

**Status**: `NOT STARTED`

When deploying the green cluster, the RGW setup is greatly simplified because buckets and S3 users are shared (no environment suffixes). The green cluster simply points to the same RGW endpoint and the same bucket names.

### 10.1 Green Cluster S3 Configuration

Since RGW lives outside the K8s lifecycle, the green cluster reuses the same S3 users and buckets:

1. **No new S3 users needed** — the same per-application users (loki, argo-artifacts, cnpg-backups, etc.) work for both clusters since buckets are shared
2. **No new buckets needed** — the plain-named buckets (loki-data, argo-artifacts, etc.) already exist
3. **Same ExternalSecrets** — the green cluster references the same Vault secrets for S3 credentials
4. **Same endpoint** — both clusters use `http://external-rgw.ceph.svc.cluster.local:80`

### 10.2 Green Cluster Secrets

The green cluster needs the same S3 credentials synced to its namespace. If the green cluster uses different namespaces, create matching ExternalSecrets that pull from the same Vault paths:

```yaml
# Example: If monitor namespace exists in green cluster
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ceph-s3-credentials
  namespace: monitor  # or whatever namespace the green cluster uses
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: ceph-s3-credentials
  data:
    - secretKey: access_key_id
      remoteRef:
        key: /core/ceph-rgw
        property: loki-access-key-id
    - secretKey: secret_access_key
      remoteRef:
        key: /core/ceph-rgw
        property: loki-secret-access-key
```

### 10.3 No Separate Backup CronWorkflow Needed

The backup CronWorkflow (Phase 6) backs up all RGW buckets to MinIO/R2 regardless of which cluster is active. There is no need for a separate green backup workflow — both clusters write to the same buckets, and the active cluster's data gets backed up.

### 10.4 Deploy Green Cluster Storage

The green cluster will use the same `ceph` namespace manifests. CSI drivers connect to the same external Ceph cluster with the same credentials. The only difference is the K8s cluster context.

---

## Phase 11: Kill-Switch Update

**Status**: `NOT STARTED`

**Manifest**: `kubernetes/manifests/automations/pipelines/kill-switch-template.yaml`

### 11.1 Redesign Kill-Switch Workflow

The kill-switch needs fundamental changes:
- **Remove Rook CRD logic** — no Rook in this architecture
- **Graceful-first approach** — let ArgoCD prune and CSI sidecars clean up
- **Add PV verification** — ensure zero orphaned data

See the updated kill-switch template in Appendix A.

### 11.2 Update and Sync

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

### 11.3 Verification (Test Kill-Switch on Non-Production)

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

## Phase 12: Cleanup Legacy Ceph Pools

**Status**: `NOT STARTED`

### 12.1 Verify SeaweedFS RBD Images Are Gone

```bash
# SSH to a Ceph monitor node
ssh root@method

# Check if any RBD images remain in osd pool
rbd ls osd

# If empty or only contains images we still need, proceed to 12.2
```

### 12.2 Remove Legacy Pools (If Safe)

```bash
# Only run if Step 12.1 confirms no needed images exist
ceph osd pool rm osd osd --yes-i-really-really-mean-it

# Review remaining pools
ceph osd pool ls
# Expected: Proxmox pools, RGW pools, and new K8s CSI pools only
```

### 12.3 Verification

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

- [x] **Phase 0**: RGW daemon running on all 3 Proxmox nodes, port 7480 reachable
- [x] **Phase 1**: ClusterIP Service + EndpointSlice deployed, port 80 → 7480 DNAT working
- [x] **Phase 2**: Admin S3 user created, can create/delete buckets from K8s (with AWS CLI v2 cosmetic 500 quirk documented)
- [x] **Phase 3**: ExternalSecrets synced, secret exists with admin credentials
- [x] **Phase 4**: All 8 buckets created and visible via `s3 ls`
- [ ] **Phase 5**: Application-specific S3 users created, credentials in secrets
- [ ] **Phase 6**: Backup CronWorkflow succeeds, data visible in MinIO
- [ ] **Phase 7**: Migration completes, file counts match between SeaweedFS and RGW
- [ ] **Phase 8**: All 6 application endpoint references updated, IngressRoute active
- [ ] **Phase 9**: SeaweedFS removed, applications continue functioning
- [ ] **Phase 10**: Green cluster S3 configuration ready (shared users/buckets, no new provisioning needed)
- [ ] **Phase 11**: Kill-switch updated and tested, no orphaned data
- [ ] **Phase 12**: Legacy pools reviewed and cleaned up
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
- Better suited for shared bucket access across blue/green clusters

**Cons**:
- No auto-scaling of RGW instances tied to K8s workloads
- Ansible-managed rather than GitOps-managed

**Acceptable trade-off**: RGW is stateless and low-resource; 3 instances across the Proxmox nodes provides redundancy.

### Bucket Management

The existing `s3-bucket-management` ClusterWorkflowTemplate (`create-or-destroy-bucket-template.yaml`) creates and destroys buckets against any S3-compatible endpoint. Pass `endpoint-url=http://external-rgw.ceph.svc.cluster.local:80` as a parameter.

### Sync Wave Dependencies

```
Phase 0: Ansible (RGW on Proxmox — one-time) ✅
  ↓
Phase 1: K8s Service/Endpoints (wave 7)
  ↓
Phase 2: Bootstrap Admin User (one-time)
  ↓
Phase 3: ExternalSecrets (wave 8)
  ↓
Phase 4: S3 Bucket Provisioning (Argo Workflow)
  ↓
Phase 5: Application S3 Users
  ↓
Phase 6: Backup CronWorkflow (wave 25)
  ↓
Phase 7: Data Migration (SeaweedFS → RGW)
  ↓
Phase 8: Cutover + Ingress Setup (wave 25)
  ↓
Phase 9: Remove SeaweedFS
  ↓
Phase 10: Green Cluster Setup (when needed)
  ↓
Phase 11: Kill-switch update
  ↓
Phase 12: Cleanup legacy pools
```

---

## Appendix C: Troubleshooting Guide

### Phase 0 Issues

**Issue**: RGW not responding on port 7480
**Solution**:
- Check service: `systemctl status ceph-radosgw@radosgw.<hostname>`
- Check firewall: `ufw allow 7480` or `iptables -L | grep 7480`
- Review RGW logs: `journalctl -u ceph-radosgw@radosgw.<hostname>`

**Issue**: Ceph RGW service fails to start
**Solution**:
- Verify Ceph cluster is HEALTH_OK: `ceph -s`
- Check RGW keyring: `cat /etc/ceph/ceph.client.radosgw.keyring`
- Check permissions: `ls -la /etc/ceph/`

### Phase 1 Issues

**Issue**: Headless Service not resolving
**Solution**:
- Verify Endpoints resource: `kubectl get endpoints external-rgw -n ceph`
- Check Service selector (should be `clusterIP: None`): `kubectl get svc external-rgw -n ceph -o yaml`
- Test DNS from pod: `kubectl run -it --rm --image=busybox test -- nslookup external-rgw.ceph.svc.cluster.local`

### Phase 2 Issues

**Issue**: S3 credentials rejected
**Solution**:
- Verify user exists: `radosgw-admin user info --uid=admin`
- Test from Proxmox first: `aws --endpoint-url http://localhost:7480 s3 ls`
- Check credentials passed correctly to pod

**Issue**: `s3 mb` returns "500 Internal Server Error" but bucket is created
**Symptoms**:
- AWS CLI v2 reports 500 error
- RGW logs show HTTP 200 for the PUT request
- Bucket actually exists (visible in `s3 ls`)

**Root Cause**: [Ceph Bug #65794](https://tracker.ceph.com/issues/65794) — RGW returns empty `<Message></Message>` tags in XML responses, causing botocore to crash when parsing `None`.

**Solution**: Use `s3api create-bucket` instead:
```bash
aws --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 \
  s3api create-bucket --bucket my-bucket
```

Or ignore the 500 error and verify with `s3 ls` — the bucket was created successfully.

### Phase 3 Issues

**Issue**: ExternalSecret not syncing
**Solution**:
- Check ExternalSecret status: `kubectl get externalsecret -n ceph`
- Verify SOPS secret exists: `kubectl get secret -n <namespace>`
- Check ExternalSecret operator logs

### Phase 4 Issues

**Issue**: Bucket creation fails via Argo workflow
**Solution**:
- Check workflow logs: `argo logs <workflow-name> -n ceph`
- Verify secret exists: `kubectl get secret ceph-external-secret -n ceph`
- Test manually from pod: `kubectl run --rm -it --image=amazon/aws-cli test -- /bin/sh`

### Phase 5 Issues

**Issue**: Application credentials not working
**Solution**:
- Verify user exists: `radosgw-admin user info --uid=<app-name>`
- Check secret contains correct keys: `kubectl get secret ceph-external-secret -n ceph -o yaml`
- Test with specific credentials

### Phase 6 Issues

**Issue**: Backup workflow fails
**Solution**:
- Check rclone config in pod
- Verify MinIO endpoint reachable: `curl http://10.0.20.199:9000`
- Check credentials for MinIO and R2
- Review workflow logs for specific bucket errors

### Phase 7 Issues

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

### Phase 8 Issues

**Issue**: Application can't connect to RGW
**Solution**:
- Verify endpoint URL is correct in config
- Check DNS resolution: `nslookup external-rgw.ceph.svc.cluster.local`
- Verify credentials are correctly referenced in secrets
- Check application logs for S3 errors

**Issue**: IngressRoute not working
**Solution**:
- Verify IngressRoute exists: `kubectl get ingressroute -n ceph`
- Check Traefik logs: `kubectl logs -n traefik deployment/traefik`
- Test directly to Service: `curl http://external-rgw.ceph.svc.cluster.local:80`

### Phase 11 Issues

**Issue**: Kill-switch leaves orphaned PVs
**Solution**:
- The `verify-pvs-gone` step will catch this
- Manually check: `kubectl get pv`
- Check Ceph for orphaned data: `rbd ls osd`, `ceph fs subvolume ls cephfs`
- Review CSI driver logs: `kubectl logs -n ceph deployment/ceph-csi-rbd-provisioner`

---

*Document generated for the bhamm-lab infrastructure migration.*
*Last updated: 2025-01-15*
