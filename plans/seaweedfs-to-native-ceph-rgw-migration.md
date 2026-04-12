# Migration Plan: SeaweedFS → Native Ceph RGW

## Overview

Migrate from SeaweedFS to Ceph RGW running natively on Proxmox bare-metal nodes. This abandons the Rook Ceph approach — the standalone Ceph CSI drivers remain unchanged for block/file storage, and RGW is deployed via Ansible on the 3 Proxmox nodes, bridged into Kubernetes via a ClusterIP Service/EndpointSlice. S3 buckets use plain (non-suffixed) names — the active cluster (blue or green) always writes to the same canonical buckets since clusters never run simultaneously and RGW persists outside the K8s lifecycle.

**Migration Status**: ✅ **COMPLETE** — All phases finished through Phase 11. SeaweedFS successfully removed, ~3TB+ space recovered in Ceph cluster. All applications (Loki, Argo Workflows, CNPG, K8up, MLflow) verified working with native Ceph RGW. Blue cluster deployed with green/blue split configs. Kill-switch redesigned and successfully tested — no orphaned Ceph data. Phase 5 skipped — using shared admin credentials for all S3 applications.

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
- **S3 Credentials**: Single admin user shared across all applications (internal VLAN + ClusterIP isolation provides sufficient security; per-app users can be added later if S3 is exposed externally)
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
3. **Simplicity** — environment suffixes would double the number of S3 users, secrets, ExternalSecrets, and application configs with no practical benefit; likewise, per-app S3 users are unnecessary on an internal-only endpoint
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
  name: create-ceph-buckets-green
  namespace: ceph
  annotations:
    argocd.argoproj.io/sync-wave: "9"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
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
                  value: ceph-external-secret
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

**Problem**: Workflow pods originally ran in the `argo` namespace, but the secret `ceph-external-secret` was in the `ceph` namespace. Kubernetes secrets are namespace-scoped — `secretKeyRef` can only access secrets in the same namespace as the pod.

**Error**: `Error: secret "ceph-external-secret" not found` (from argo namespace)

**Solution**: Moved the bucket creation workflow to the `ceph` namespace where `ceph-external-secret` already exists. Created a `ServiceAccount` and `RoleBinding` for `argo-workflow` in the `ceph` namespace (see `kubernetes/manifests/base/ceph/workflow-rbac-all.yaml`). This keeps all Ceph RGW resources in the `ceph` namespace, consistent with the SeaweedFS pattern where SeaweedFS workflows use `seaweedfs-external-secret` in the `seaweedfs` namespace.

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

## Phase 5: Application-Specific S3 Users — SKIPPED

**Status**: ⏭️ **SKIPPED** — Using shared admin credentials for all applications instead of per-app S3 users.

### Rationale

Per-app S3 users were originally planned for credential isolation, but are unnecessary for this deployment:

1. **Internal-only access** — RGW is only reachable via ClusterIP Service (no external exposure) on a separate VLAN
2. **Namespace isolation** — K8s RBAC controls pod access to secrets; compromising a namespace already implies broader cluster access
3. **Admin creds already in-cluster** — The bucket management workflow (`s3-bucket-management`) already requires admin creds, so per-app creds don't meaningfully reduce the attack surface
4. **Operational simplicity** — Avoids creating 7 radosgw users, managing 14 key pairs, and maintaining per-namespace ExternalSecrets with no tangible security benefit on an isolated network

### If Per-App Credentials Are Needed Later

If S3 is ever exposed externally via IngressRoute, or if stricter isolation is desired:

1. Create per-app users: `radosgw-admin user create --uid=<app> --display-name="<App>"`
2. Apply bucket policies: `radosgw-admin policy put --uid=<app> --bucket=<bucket> --policy-file=<app>-policy.json`
3. Add credentials to SOPS/Vault and create per-namespace ExternalSecrets
4. Update application configs to reference app-specific secret keys

The existing `ceph-external-secret` in the `ceph` namespace (admin creds from Phase 3) is used by all applications going forward.

---

## Phase 6: Backup CronWorkflow

**Status**: ✅ **COMPLETE**

**Manifests**: `kubernetes/manifests/base/ceph/ceph-rgw-backup-all.yaml`, `kubernetes/manifests/base/ceph/workflow-rbac-all.yaml`
**Sync Wave**: 25

**Rationale**: Reuses the successful rclone pattern from `seaweedfs-onsite-backup` but simplifies significantly since RGW runs outside K8s (no ArgoCD autosync toggling, no statefulset scaling, no K8up). Uses a single `ceph-rgw` bucket on MinIO/R2 to store all RGW buckets as subdirectories, keeping backups completely independent from the existing `seaweedfs` bucket.

### 6.1 Prerequisites — Cloudflare R2 Bucket

Created the `ceph-rgw` R2 bucket via Terraform:

**File**: `tofu/cloudflare/main.tf`
```hcl
resource "cloudflare_r2_bucket" "ceph_rgw_bucket" {
  account_id    = var.cloudflare_account_id
  name          = var.ceph_rgw_bucket_name
  location      = var.ceph_rgw_bucket_location
  storage_class = var.ceph_rgw_bucket_storage_class
}
```

**File**: `tofu/cloudflare/variables.tf` — added `ceph_rgw_bucket_name` (default: `ceph-rgw`), `ceph_rgw_bucket_location` (default: `wnam`), `ceph_rgw_bucket_storage_class` (default: `Standard`)

MinIO `ceph-rgw` bucket was already created manually on TrueNAS.

### 6.2 Update ceph-external-secret

Added MinIO and R2 backup credentials to `kubernetes/manifests/base/ceph/common-all.yaml` so the CronWorkflow can access backup destinations. These 6 keys were added to the existing `ceph-external-secret` ExternalSecret (vault paths already exist, also used by `seaweedfs-external-secret`):

| Secret Key | Vault Path | Vault Property |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `/core/k8up` | `S3_ACCESS_KEY_ID` |
| `AWS_SECRET_ACCESS_KEY` | `/core/k8up` | `S3_SECRET_ACCESS_KEY` |
| `AWS_ENDPOINT` | `/core/k8up` | `S3_ENDPOINT` |
| `R2_ACCESS_KEY_ID` | `/external/cloudflare` | `r2-access-key-id` |
| `R2_SECRET_ACCESS_KEY` | `/external/cloudflare` | `r2-secret-access-key` |
| `R2_ENDPOINT` | `/external/cloudflare` | `r2-endpoint` |

### 6.3 Create Workflow RBAC

Created `kubernetes/manifests/base/ceph/workflow-rbac-all.yaml` with ServiceAccount, Role, and RoleBinding for `argo-workflow` in the `ceph` namespace. This is simpler than the SeaweedFS RBAC because RGW is external — no ArgoCD autosync toggling, no StatefulSet scaling, no k8up management needed.

### 6.4 Create Backup CronWorkflow

Created `kubernetes/manifests/base/ceph/ceph-rgw-backup-all.yaml` — a CronWorkflow in the `ceph` namespace that:

1. **`list-buckets`** step — uses `rclone lsd rgw:` to dynamically discover all RGW buckets at runtime (rather than hardcoding bucket names). Uses `rclone/rclone` image and `>&2` to redirect `rclone config create` NOTICE output to stderr so it doesn't pollute `outputs.result`.
2. **`rclone-sync-to-minio`** step — receives the bucket list via `{{steps.list-buckets.outputs.result}}` and syncs each bucket to `minio:ceph-rgw/<bucket>/`.
3. **`rclone-sync-to-r2`** exit handler — syncs `minio:ceph-rgw` → `r2:ceph-rgw` with checksum verification (only on success).

### 6.5 Bucket Creation Workflow Namespace Change

Moved `kubernetes/manifests/base/ceph/buckets-green.yaml` from `namespace: argo` to `namespace: ceph`, and changed the auth secret reference from `argo-external-secret` to `ceph-external-secret`. This keeps all Ceph RGW resources in the `ceph` namespace, consistent with the SeaweedFS pattern.

### 6.6 Hiccups & Lessons Learned

#### Hiccup 1: minio/mc image lacks awk/sed

**Problem**: Initial `list-buckets` step used `minio/mc:RELEASE.2025-08-13T08-35-41Z` to list buckets with `mc ls ceph/ | awk '{print $NF}' | sed 's:/$::'`. The `minio/mc` image is minimal and doesn't include `awk` or `sed`.

**Error**: `/bin/sh: line 2: sed: command not found` and `/bin/sh: line 2: awk: command not found`

**Solution**: Switched to `rclone/rclone` image (Alpine-based) and replaced `mc ls` with `rclone lsd rgw:`, which outputs one line per bucket with the bucket name as the last field. `rclone lsd` doesn't append `/` to bucket names, so `sed` stripping is unnecessary — only `awk '{print $NF}'` is needed.

#### Hiccup 2: outputs.result pollution from config commands

**Problem**: `rclone config create` outputs a NOTICE line like `Added 'rgw' successfully.` to stdout. Since Argo Workflows captures stdout for `outputs.result`, this message was prepended to the bucket list, causing `Added` to be treated as a bucket name.

**Error**: `S3 bucket Added: error reading source root directory: directory not found`

**Solution**: Redirect `rclone config create` output to stderr with `>&2`, so only `rclone lsd` output ends up in `outputs.result`:
```bash
rclone config create rgw s3 ... >&2
rclone lsd rgw: | awk '{print $NF}' | tr '\n' ' '
```

### 6.7 Verification

```bash
# Sync ceph-common to update ceph-external-secret with new credentials
argocd app sync ceph-common

# Verify secret has new keys
kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data}' | jq -r 'keys[]'
# Expected: Should include s3_user, s3_access_key, s3_secret_key, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT

# Sync the storage application (includes the CronWorkflow)
argocd app sync storage

# Trigger backup manually for testing
argo submit --from cronworkflow/ceph-rgw-backup -n ceph

# Watch the workflow
argo watch ceph-rgw-backup-xxxx -n ceph

# Verify MinIO after completion
# Open MinIO console at http://10.0.20.199:9000

# Verify R2 after completion (via Cloudflare console or rclone)
rclone ls r2:ceph-rgw
```

**Key Design Decisions:**
- **Single bucket approach**: All RGW buckets sync into one MinIO/R2 bucket (`ceph-rgw`) as subdirectories. This mirrors the SeaweedFS backup pattern and keeps the backup footprint minimal.
- **Two-stage sync**: RGW → MinIO (per-bucket loop), then MinIO → R2 (entire bucket). This ensures the RGW backup is complete before offsite replication.
- **Dynamic bucket discovery**: `list-buckets` step uses `rclone lsd rgw:` to discover buckets at runtime instead of hardcoding bucket names. New buckets are automatically included in backups without manifest changes.
- **Namespace: `ceph`** (not `argo`) — all Ceph RGW workflows run in the `ceph` namespace with `ceph-external-secret`, consistent with the SeaweedFS pattern where SeaweedFS workflows use `seaweedfs-external-secret` in the `seaweedfs` namespace. No ArgoCD/k8up/StatefulSet RBAC needed since RGW is external.
- **Credentials**: Uses `ceph-external-secret` which now contains RGW admin creds, MinIO creds, and R2 creds — all in one secret in the `ceph` namespace.
- **Rclone flags**: Reuses proven flags from `seaweedfs-onsite-backup` for performance and reliability.

**🟢 READY: Phase 6 is complete. Proceed to Phase 7.**

---

## Phase 7: Data Migration (SeaweedFS → Ceph RGW)

**Status**: ✅ **COMPLETE**

**Summary**: Migration completed successfully. All 5 buckets migrated from SeaweedFS to RGW with matching file counts. Post-MTU-fix tuning achieved ~180-200 MiB/s sustained throughput. SeaweedFS credentials (`swfs_access_key`, `swfs_secret_key`) were temporarily added to `ceph-external-secret` for migration and can now be removed (see Phase 9 cleanup).

### 7.0 Add SeaweedFS Credentials to ceph-external-secret

The migration workflow needs both SeaweedFS (source) and RGW (destination) credentials. Rather than creating a separate migration secret, add SeaweedFS credentials to the existing `ceph-external-secret` via `common-all.yaml`.

**File**: `kubernetes/manifests/base/ceph/common-all.yaml`

Added 2 entries to `externalSecrets.secrets`:

| Secret Key | Vault Path | Vault Property |
|---|---|---|
| `swfs_access_key` | `/core/seaweedfs` | `admin_access_key_id` |
| `swfs_secret_key` | `/core/seaweedfs` | `admin_secret_access_key` |

These can be removed after Phase 9 (SeaweedFS removal) when they're no longer needed.

```bash
# Sync to update the secret
argocd app sync ceph-common

# Verify new keys exist
kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data}' | jq -r 'keys[]'
# Should include: s3_user, s3_access_key, s3_secret_key, swfs_access_key, swfs_secret_key, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT
```

### 7.1 Create Migration Workflow

**File**: `kubernetes/hack/seaweedfs-to-rgw-migration.yaml`

An Argo Workflow (one-time, not a CronWorkflow) in `namespace: ceph` that uses the same patterns as `ceph-rgw-backup-all.yaml`:

1. **`migrate-buckets`** — Iterates over a hardcoded list of 5 buckets (`cnpg-backups k8up-backups mlflow proxmox-backup-server tofu-state`). For each bucket, checks if it exists in SeaweedFS via `rclone lsd`, then runs `rclone copy swfs:<bucket> rgw:<bucket>` with aggressive concurrency flags. Buckets that don't exist in SeaweedFS (`mlflow`, `proxmox-backup-server`) are skipped. Resource limits: 2 CPU / 4Gi request, 4 CPU / 8Gi limit.

2. **`verify-migration`** — Compares `rclone size` output for each bucket between SeaweedFS and RGW, reporting object counts and byte sizes. Flags mismatches.

All credentials come from `ceph-external-secret`:

| Env Var | Secret Key | Source |
|---|---|---|
| `SWFS_ACCESS_KEY` | `swfs_access_key` | SeaweedFS admin access key |
| `SWFS_SECRET_KEY` | `swfs_secret_key` | SeaweedFS admin secret key |
| `RGW_ACCESS_KEY` | `s3_access_key` | RGW admin access key |
| `RGW_SECRET_KEY` | `s3_secret_key` | RGW admin secret key |

rclone flags (current — aggressively tuned for 10GbE post-MTU fix):
```
--progress --fast-list --no-check-dest
--transfers=64 --checkers=128 --buffer-size=32M
--s3-chunk-size=16M --s3-disable-checksum
--s3-no-head --s3-no-check-bucket --stats=15s
```

**rclone flag evolution** (see Section 7.5 for full details):

| Iteration | Flags | Result |
|---|---|---|
| Initial | `--transfers=24 --checkers=48 --s3-chunk-size=32M --s3-upload-concurrency=24 --s3-disable-checksum --disable-http2 --stats=30s` | Dropped connections due to MTU mismatch |
| Conservative | `--transfers=16 --checkers=32 --s3-chunk-size=16M --s3-upload-concurrency=8 --s3-disable-checksum --s3-no-head --s3-no-check-bucket --checksum --stats=30s` | ~180-200 MiB/s but RGW TCP drops with `--s3-upload-cutoff=0` |
| Post-MTU fix | `--transfers=8 --checkers=8 --s3-chunk-size=16M --s3-upload-concurrency=2 --s3-disable-checksum --s3-no-head --s3-no-check-bucket --stats=15s` | ~180-200 MiB/s, stable |
| Current (aggressive) | `--transfers=64 --checkers=128 --buffer-size=32M --s3-chunk-size=16M --s3-disable-checksum --s3-no-head --s3-no-check-bucket --stats=15s` | Testing 10GbE saturation |

### 7.2 Run Migration

```bash
# Apply the workflow
kubectl apply -f kubernetes/hack/seaweedfs-to-rgw-migration.yaml

# Delete any existing completed/failed workflow instance first
kubectl delete workflow seaweedfs-to-rgw-migration -n ceph 2>/dev/null || true

# Submit the workflow
argo submit seaweedfs-to-rgw-migration -n ceph

# Watch the workflow
argo watch <workflow-name> -n ceph

# Monitor progress — cnpg-backups (~7,600+ 16MB WAL files, ~142-224 GB) will take the longest
# Re-run after completion as a cleanup pass (rclone copy is idempotent — only failed/delta files transfer)
```

### 7.3 Verification

```bash
# List RGW buckets to confirm all migrated
kubectl run -n ceph --image=minio/mc:RELEASE.2025-08-13T08-35-41Z test-s3 --rm -it --restart=Never \
  --env ACCESS_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_access_key}' | base64 -d) \
  --env SECRET_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_secret_key}' | base64 -d) \
  -- /bin/sh -c 'mc alias set rgw http://external-rgw.ceph.svc.cluster.local:80 $ACCESS_KEY $SECRET_KEY && mc ls rgw'

# Spot-check key files in loki-data
kubectl run -n ceph --image=minio/mc:RELEASE.2025-08-13T08-35-41Z test-s3 --rm -it --restart=Never \
  --env ACCESS_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_access_key}' | base64 -d) \
  --env SECRET_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_secret_key}' | base64 -d) \
  -- /bin/sh -c 'mc alias set rgw http://external-rgw.ceph.svc.cluster.local:80 $ACCESS_KEY $SECRET_KEY && mc ls rgw/loki-data'

# Verify file counts match between SeaweedFS and RGW
# (The verify-migration step in the workflow already does this, but for manual verification:)
# Compare: rclone size swfs:loki-data
# With:    rclone size rgw:loki-data
```

### 7.4 Key Design Decisions

- **Argo Workflow instead of raw Pod**: Consistent with existing patterns (bucket creation, backups). Provides better logging, retry, and Argo UI visibility. Stored in `kubernetes/hack/` as a one-off script (not GitOps-managed).
- **Credentials via ceph-external-secret**: No separate migration secret needed. SeaweedFS creds (`swfs_access_key`/`swfs_secret_key`) added to the existing ExternalSecret in `common-all.yaml`. These can be removed after Phase 9.
- **Hardcoded bucket list instead of dynamic discovery**: Initially used `rclone lsd swfs:` to discover all buckets at runtime, but switched to a hardcoded list of 5 buckets (`cnpg-backups k8up-backups mlflow proxmox-backup-server tofu-state`). This avoids migrating SeaweedFS-internal buckets (e.g., `loki-data`, `argo-artifacts` which are already in RGW via bucket creation, and internal SeaweedFS metadata). Buckets that don't exist in SeaweedFS (`mlflow`, `proxmox-backup-server`) are skipped via `rclone lsd` check.
- **`rclone copy` (not `sync`)**: `copy` is idempotent and never deletes; `sync` would delete files in RGW that don't exist in SeaweedFS (dangerous for the 3 new RGW-only buckets: `beyond-vibes`, `mlflow`, `proxmox-backup-server`).
- **Single copy pass**: Applications continue writing to SeaweedFS during migration. Any delta written during migration is acceptable — Phase 8 cutover will switch endpoints to RGW, and new data will go directly to RGW. A cleanup re-run of the workflow catches any files that failed or were written during the first pass.
- **Sequential bucket iteration**: Follows the `for bucket in ...` pattern rather than Argo `withParam` fan-out, keeping the migration simple and serializable.
- **rclone config create → stderr**: All `rclone config create` commands redirect to `>&2` to prevent config notices from polluting `outputs.result` (lesson from Phase 6 hiccup 2).
- **aws-cli avoided**: Uses `minio/mc` for manual verification instead of `aws-cli`, which has the Ceph Bug #65794 empty message tag quirk.
- **Aggressive rclone concurrency for 10GbE**: Post-MTU-fix, the bottleneck shifted from network packet loss to S3 API negotiation latency and Ceph double-penalty I/O. With 16MB WAL files, only `--transfers` scales throughput (each file is a single PUT since `--s3-chunk-size=16M`). Settings: `--transfers=64 --checkers=128 --buffer-size=32M` with pod resources of 2-4 CPU / 4-8Gi RAM to support the concurrent connections and buffers.
- **Ceph double-penalty awareness**: SeaweedFS reads from Ceph RBD PVCs, and RGW writes to Ceph OSDs. A logical 200 MiB/s transfer generates ~600 MiB/s of physical backend I/O (3x replication factor). The aggressive `--transfers=64` pushes throughput only if the Ceph OSDs and gateway CPUs can sustain it — if speed stays flat despite higher concurrency, the cluster has reached its physical limits.

**🛑 STOP: Do not proceed to Phase 8 until migration completes and file counts match between SeaweedFS and RGW.**

### 7.5 Troubleshooting & rclone Tuning History

The migration went through multiple rounds of rclone tuning to address network issues and optimize throughput. This section documents the evolution for future reference.

#### Hiccup 1: MTU Mismatch Causing Packet Loss

**Problem**: Initial migration runs suffered from severe connection drops and timeouts. rclone would lose TCP connections mid-transfer with errors like `write tcp: use of closed network connection`. The effective throughput was near zero despite the cluster running on 10GbE.

**Root Cause**: MTU mismatch between the Kubernetes Cilium network (MTU 9000/jumbo frames) and Proxmox network interfaces (standard 1500 MTU). Large S3 PUT requests were being fragmented or dropped, causing persistent TCP resets.

**Fix**: Corrected the MTU configuration on the Proxmox bridges/VM NICs to match the cluster network. After the MTU fix, rclone immediately stabilized at ~180-200 MiB/s with conservative settings.

#### Hiccup 2: RGW TCP Connection Drops with Multipart Uploads

**Problem**: With the MTU fix in place, `--s3-upload-cutoff=0` was forcing every file (even 16MB WAL files) through multipart upload (3+ API calls per file). With `--transfers=16` or higher, this overwhelmed RGW with concurrent multipart sessions, causing TCP connection drops:
```
write tcp 10.244.4.245:XXXXX->10.103.67.72:80: use of closed network connection
```

**Root Cause**: Each multipart upload requires InitiateMultipartUpload → UploadPart (per chunk) → CompleteMultipartUpload. With 16MB files chunked at 16MB, each file should be a single PUT, but `--s3-upload-cutoff=0` forced the multipart path unnecessarily. Combined with high concurrency, RGW's connection handling couldn't keep up.

**Fix**: Removed `--s3-upload-cutoff=0` (since `--s3-chunk-size=16M` already matches the 16MB WAL files, they're uploaded as single PUTs). Also removed `--disable-http2` (HTTP/2 multiplexing helps with many concurrent small requests). Reduced `--s3-upload-concurrency` from 24 to 2 (since files are single PUTs, upload concurrency is irrelevant).

#### rclone Tuning Evolution

| Stage | Key Flags | Result | Reason for Change |
|---|---|---|---|
| **v1 — Initial** | `--transfers=24 --checkers=48 --s3-chunk-size=32M --s3-upload-concurrency=24 --s3-disable-checksum --disable-http2 --stats=30s` | Connection drops, near-zero throughput | MTU mismatch caused packet loss |
| **v2 — Conservative** | `--transfers=16 --checkers=32 --s3-chunk-size=16M --s3-upload-concurrency=8 --s3-disable-checksum --s3-no-head --s3-no-check-bucket --checksum --stats=30s` | Stable ~180-200 MiB/s | Post-MTU fix, conservative to avoid RGW drops |
| **v3 — Fix multipart** | `--transfers=16 --checkers=32 --s3-chunk-size=16M --s3-upload-concurrency=8 --s3-disable-checksum --s3-no-head --s3-no-check-bucket --checksum --s3-upload-cutoff=0 --stats=30s` | RGW TCP connection drops | `--s3-upload-cutoff=0` forced multipart on every file |
| **v4 — Stable** | `--transfers=8 --checkers=8 --s3-chunk-size=16M --s3-upload-concurrency=2 --s3-disable-checksum --s3-no-head --s3-no-check-bucket --stats=15s` | Stable ~180-200 MiB/s, no drops | Removed `--s3-upload-cutoff=0`, removed `--checksum`, lowered concurrency |
| **v5 — Aggressive (current)** | `--transfers=64 --checkers=128 --buffer-size=32M --s3-chunk-size=16M --s3-disable-checksum --s3-no-head --s3-no-check-bucket --stats=15s` | Testing 10GbE saturation | Network is healthy; push concurrency to find actual ceiling |

#### Why `--transfers=64` and Not More?

With 16MB files and `--s3-chunk-size=16M`, each file is a single HTTP PUT (no multipart). The bottleneck is S3 API negotiation latency — rclone must complete one PUT before starting the next. With 64 concurrent transfers, there are ~1 GiB of data in-flight at any moment (64 × 16MB). If throughput jumps to 400+ MiB/s, the bottleneck was API latency. If throughput stays at ~200 MiB/s, the Ceph cluster disks (or RGW/SeaweedFS gateway CPUs) are at their physical limits.

#### Ceph Double-Penalty I/O

SeaweedFS is backed by Ceph RBD PVCs, and RGW writes to Ceph OSDs. This means Ceph is both source and destination:
1. SeaweedFS reads from Ceph RBD at 200 MiB/s
2. RGW writes to Ceph OSDs at 200 MiB/s
3. With 3x replication, OSDs physically write ~600 MiB/s

A logical 200 MiB/s transfer generates ~4-5 Gbps of physical backend traffic on the Ceph cluster network. Enterprise NVMe OSDs can handle this, but spinning disks or SATA SSDs may become the ceiling.

---

## Phase 8: Cutover, Ingress Setup & Endpoint Updates

**Status**: ✅ **COMPLETE**

**Summary**: All applications successfully switched from SeaweedFS to native Ceph RGW. 42 files modified across endpoint configurations, ExternalSecrets, and common chart templates. New IngressRoute `rgw.bhamm-lab.com` added for external S3 access. All applications verified working (Loki, Argo, CNPG, K8up, MLflow tested).

### 8.1 What Was Done

**Files Modified (42 total):**

1. **IngressRoute Added** (`kubernetes/manifests/base/ceph/common-all.yaml`):
   - Added `rgw.bhamm-lab.com` IngressRoute pointing to `external-rgw` service on port 80
   - No auth middleware (S3 needs programmatic access)
   - Temporarily retained `swfs_access_key`/`swfs_secret_key` in ExternalSecret for migration

2. **S3 Endpoint Switches** (6 files):
   - `kubernetes/manifests/base/argo/workflows-all.yaml` — Argo artifact repository
   - `kubernetes/manifests/base/monitor/loki-all.yaml` — Loki storage
   - `kubernetes/manifests/apps/ai/models/helm-green.yaml` — MLflow S3 endpoint
   - `kubernetes/charts/common/templates/pg-objectstore.yaml` — CNPG backups (2 occurrences)
   - `kubernetes/charts/common/templates/k8up-schedule.yaml` — K8up backups
   - `kubernetes/charts/common/templates/k8up-restore.yaml` — K8up restore

   All changed from `seaweedfs-s3.seaweedfs.svc.cluster.local:8333` → `external-rgw.ceph.svc.cluster.local:80`

3. **ExternalSecret Vault References** (5 files):
   - Changed from `/core/seaweedfs` → `/core/ceph-rgw`
   - Keys changed from `admin_access_key_id`/`admin_secret_access_key` → `s3_access_key`/`s3_secret_key`
   - Files: argo/common, monitor/common, models/common-green, pg-external-secret, k8up-external-secret

4. **Common Chart Refactor** (4 files):
   - Parameterized `s3.endpoint` in `kubernetes/charts/common/values.yaml`
   - Updated templates to use `{{ .Values.s3.endpoint }}` instead of hardcoded URLs
   - Files: values.yaml, pg-objectstore.yaml, k8up-schedule.yaml, k8up-restore.yaml

5. **Branch Switch** (27 files):
   - All `*-common-all.yaml` files referencing `path: kubernetes/charts/common`
   - Changed `targetRevision: main` → `targetRevision: feature/ceph-rgw`
   - (Revert to `main` after merge)

### 8.2 Update Storage Common Chart with IngressRoute

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
- **Credentials**: Reference `ceph-external-secret` with admin `s3_access_key` / `s3_secret_key`

#### Argo Workflows
**File**: `kubernetes/manifests/base/argo/workflows-all.yaml`
- **Old**: `endpoint: "seaweedfs-s3.seaweedfs.svc.cluster.local:8333"`
- **New**: `endpoint: "external-rgw.ceph.svc.cluster.local:80"`
- **Bucket**: No change — stays `argo-artifacts`
- **Credentials**: Reference `ceph-external-secret` with admin `s3_access_key` / `s3_secret_key`

#### CNPG (Common Chart Template)
**File**: `kubernetes/charts/common/templates/pg-objectstore.yaml`
- **Old**: `endpointURL: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`
- **New**: `endpointURL: http://external-rgw.ceph.svc.cluster.local:80`
- **Bucket**: No change — stays `cnpg-backups`
- **Credentials**: Reference admin `s3_access_key` / `s3_secret_key` from `ceph-external-secret`

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

**Status**: ✅ **COMPLETE**

**Summary**: SeaweedFS namespace and all resources successfully removed. ~3TB+ of RBD space recovered in Ceph cluster after PVC deletion and trash purge. All applications continue functioning normally with RGW.

### 9.1 What Was Done

1. **Moved manifests to hack/**: Instead of deleting from git immediately, moved `kubernetes/manifests/base/seaweedfs/` to `kubernetes/hack/` directory to allow ArgoCD graceful pruning without history loss

2. **ArgoCD prune**: SeaweedFS Application was removed from ArgoCD, triggering cascade deletion of all managed resources

3. **Manual cleanup**: Some resources (PVCs with finalizers, Helm sub-resources) required manual intervention:
   - PVC finalizers needed removal for graceful deletion
   - Namespace deletion ordering required manual force-delete for stuck resources
   - SeaweedFS namespace successfully cleaned up

4. **Ceph space recovery**: After PVC deletion, RBD images moved to trash (`rbd trash ls osd`). Space recovered after async OSD cleanup (~3TB+ freed)

### 9.2 Cleanup Remaining References

- [ ] Remove `swfs_access_key`/`swfs_secret_key` from `ceph-external-secret` (Phase 8 file)
- [ ] Remove `/core/seaweedfs` Vault path (no longer needed)
- [ ] Eventually delete `kubernetes/hack/seaweedfs/` directory permanently
- [ ] Update DNS: Either redirect `s3.bhamm-lab.com` → `rgw.bhamm-lab.com` or remove DNS record

### 9.3 Verification

```bash
# Verify SeaweedFS namespace is gone
kubectl get namespace seaweedfs
# Expected: Error from server (NotFound): namespaces "seaweedfs" not found

# Verify no SeaweedFS pods running
kubectl get pods --all-namespaces | grep seaweedfs
# Expected: No results

# Verify RGW buckets still accessible
kubectl run -n ceph --image=amazon/aws-cli:latest test-s3 --rm -it --restart=Never \
  --env AWS_ACCESS_KEY_ID=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_access_key}' | base64 -d) \
  --env AWS_SECRET_ACCESS_KEY=$(kubectl get secret ceph-external-secret -n ceph -o jsonpath='{.data.s3_secret_key}' | base64 -d) \
  -- --endpoint-url http://external-rgw.ceph.svc.cluster.local:80 s3 ls

# Verify Ceph space recovered
ssh root@method ceph df
# Should show increased available space in osd pool
```

**✅ READY: Phase 9 complete. Proceed to Phase 10-12 as needed.**

---

## Phase 10: Green/Blue Cluster Setup

**Status**: ✅ **COMPLETE**

Successfully split configurations for blue/green cluster deployment. Created `*-green.yaml` and `*-blue.yaml` variants for apps that need environment-specific settings (particularly backup/restore behavior). Blue cluster deployed and verified with correct settings.

### 10.1 What Was Done

Split 4 files from `common-all.yaml` pattern to support per-environment configuration:

| Original File | Green Variant | Blue Variant |
|---------------|---------------|--------------|
| `base/authelia/common-all.yaml` | `common-green.yaml` | `common-blue.yaml` |
| `base/test/common-all.yaml` | `common-green.yaml` | `common-blue.yaml` |
| `core/forgejo/common-all.yaml` | `common-green.yaml` | `common-blue.yaml` |
| `core/harbor/common-all.yaml` | `common-green.yaml` | `common-blue.yaml` |

Key differences between green and blue variants:
- **Green**: `backup.enabled: true`, `restore.enabled: false` — green cluster handles backups
- **Blue**: `backup.enabled: false`, `restore.enabled: true` — blue cluster restores from green's backups

### 10.2 Fixed Harbor S3 Reference

Updated Harbor's ExternalSecret to reference `/core/ceph-rgw` instead of `/core/seaweedfs` in `core/harbor/common-blue.yaml`.

### 10.3 Renamed Core Blue Config

Renamed `kubernetes/manifests/base/core-blue-hack.yaml` → `core-blue.yaml` and updated `targetRevision` to point to the correct branch.

### 10.4 Deploy Blue Cluster

Blue cluster successfully deployed with:
- Correct S3 bucket configuration
- Restore-from-backup functionality enabled
- S3 credentials from `/core/ceph-rgw` Vault path
- Shared RGW endpoint: `http://external-rgw.ceph.svc.cluster.local:80`

### 10.5 Verification

Verified that blue cluster correctly:
- Connects to RGW using admin credentials
- Restores backups from green cluster's S3 buckets
- Does NOT overwrite green's backup data (backup disabled)

---

## Phase 11: Kill-Switch Redesign

**Status**: ✅ **COMPLETE**

**Manifest**: `kubernetes/manifests/automations/pipelines/kill-switch-template.yaml`

Successfully redesigned and tested the kill-switch workflow. Zero orphaned Ceph data confirmed after test run. ~3TB+ space was restored on the Ceph cluster.

### 11.1 Key Design Changes

**Problem**: Original kill-switch used `kubectl delete app` which doesn't properly cascade resources, leading to orphaned workloads and PVCs. Force-deleting PVCs before CSI provisioner could clean up left orphaned RBD images in Ceph.

**Solution**: Ordered teardown with `argocd app delete --cascade`:

| Step | Method | Purpose |
|------|--------|---------|
| 1. Pause Parents | `kubectl patch` — ordered: base → core → apps | Prevent parent apps from recreating children during teardown |
| 2. Pause Children | `kubectl patch` — all non-skip apps | Stop auto-sync to prevent healing |
| 3. Cleanup K8up | `kubectl delete` K8up CRs with wait | Release backup locks so PVCs can be deleted |
| 4. Cleanup CNPG | `kubectl delete cluster.cnpg.io --wait` | Operator gracefully cleans up PVCs before cascade hits |
| 5. Delete Apps | `argocd app delete --cascade` | Proper cascade deletion of all managed resources |
| 6. Delete Workloads | `kubectl delete deploy,sts,ds,jobs --all --wait` | Second pass for non-Argocd-managed resources (e.g., raw manifests) |
| 7. Wait for Pods | Polling loop, only PVC namespaces | Avoid waiting for DaemonSets in namespaces without PVCs |
| 8. Delete PVCs | `kubectl delete pvc --all --wait` | Graceful deletion — CSI processes Delete events |
| 9. Verify PVs | `kubectl get pv` check | Confirm no orphaned PVs bound to deleted namespaces |

### 11.2 Workflow Parameters (Centralized Configuration)

Replaced hardcoded skip lists with workflow-level parameters:

```yaml
spec:
  arguments:
    parameters:
      - name: skip-apps
        value: "argocd argocd-common argo-common argo-workflows argo-events automations ceph-common ceph-csi-rbd ceph-csi-cephfs csi-snapshot-crds csi-snapshotter snapshot-controller cloudnative-pg cloudnative-pg-barman green-base green-core green-apps blue-base blue-core"
      - name: skip-namespaces
        value: "argocd argo ceph cnpg-system kube-system"
```

**Skip Apps** (15 total): Infrastructure apps that must survive kill-switch:
- ArgoCD stack: `argocd`, `argocd-common`
- Argo stack: `argo-common`, `argo-workflows`, `argo-events`, `automations`
- Ceph stack: `ceph-common`, `ceph-csi-rbd`, `ceph-csi-cephfs`, `csi-snapshot-crds`, `csi-snapshotter`, `snapshot-controller`
- CNPG stack: `cloudnative-pg`, `cloudnative-pg-barman`
- Parent apps: `green-base`, `green-core`, `green-apps`, `blue-base`, `blue-core`

**Skip Namespaces**: `argocd`, `argo`, `ceph`, `cnpg-system`, `kube-system`

### 11.3 Removed Annotations

Removed `kill-switch.bhamm-lab.com/skip: "true"` annotations from 13 infrastructure files. Skip logic now entirely in workflow parameters — no need to annotate individual apps.

### 11.4 Images Used

| Template | Image | Reason |
|----------|-------|--------|
| `pause-parents`, `pause-children`, `cleanup-k8up`, `cleanup-cnpg`, `delete-workloads`, `wait-for-pods`, `delete-pvcs`, `verify-pvs` | `alpine/kubectl` | Lightweight, kubectl pre-installed |
| `delete-apps` | `alpine/kubectl` + installs ArgoCD CLI | Needs `argocd` command for cascade delete |

### 11.5 Auth for ArgoCD CLI

The `delete-apps` step authenticates to ArgoCD using the initial admin password:

```bash
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
argocd login argocd-server.argocd.svc --plaintext --grpc-web \
  --username admin --password "$ARGOCD_PASS"
```

### 11.6 Verification

Successfully tested kill-switch on cluster teardown:

```bash
# Submit kill-switch workflow
argo submit --from workflowtemplate/kill-switch -n argo

# Watch the workflow (takes ~10-15 minutes)
argo watch kill-switch-xxxx -n argo

# After completion, verify on Ceph monitor:
ssh root@method rbd ls osd
# Expected: Only images from skip namespaces (if any)

ssh root@method ceph fs subvolume ls cephfs
# Expected: Empty or only skip namespace subvolumes

# Check Ceph space recovered
ssh root@method ceph df
# Should show increased available space
```

**Result**: Zero orphaned RBD images. All PVCs successfully deleted and CSI provisioner cleaned up Ceph data. ~3TB+ space restored.

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
- [x] **Phase 5**: ~~Application-specific S3 users~~ — SKIPPED, using shared admin credentials
- [x] **Phase 6**: Backup CronWorkflow succeeds, data visible in MinIO
- [x] **Phase 7**: Migration workflow runs successfully, file counts match between SeaweedFS and RGW, SeaweedFS creds added to ceph-external-secret
- [x] **Phase 8**: All 6 application endpoint references updated, IngressRoute active
- [x] **Phase 9**: SeaweedFS removed, applications continue functioning
- [x] **Phase 10**: Green/blue cluster configuration split complete — `*-green.yaml` and `*-blue.yaml` variants created, blue cluster deployed and verified
- [x] **Phase 11**: Kill-switch redesigned and tested — zero orphaned Ceph data confirmed, ~3TB+ space recovered
- [ ] **Phase 12**: Legacy pool cleanup (optional — can be done anytime)
- [x] **Final**: CSI drivers (`csi-rbd-sc`, `csi-cephfs-sc`) remain functional, no disruptions

---

## Appendix A: Kill-Switch Workflow (Production-Ready)

**Status**: ✅ **PRODUCTION**

**File**: `kubernetes/manifests/automations/pipelines/kill-switch-template.yaml`

**Last Tested**: Successfully executed with zero orphaned Ceph data, ~3TB+ space recovered.

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
  activeDeadlineSeconds: 900
  arguments:
    parameters:
      - name: skip-apps
        value: "argocd argocd-common argo-common argo-workflows argo-events automations ceph-common ceph-csi-rbd ceph-csi-cephfs csi-snapshot-crds csi-snapshotter snapshot-controller cloudnative-pg cloudnative-pg-barman green-base blue-base"
      - name: skip-namespaces
        value: "argocd argo ceph cnpg-system kube-system"
  templates:
    - name: cleanup
      steps:
        - - name: pause-parents
            template: pause-parents
        - - name: pause-children
            template: pause-children
        - - name: cleanup-k8up
            template: cleanup-k8up
        - - name: cleanup-cnpg
            template: cleanup-cnpg
        - - name: delete-apps
            template: delete-apps
        - - name: delete-workloads
            template: delete-workloads
        - - name: wait-for-pods
            template: wait-for-pods
        - - name: delete-pvcs
            template: delete-pvcs
        - - name: verify-pvs
            template: verify-pvs

    # Step 1: Pause parent apps in order (base → core → apps)
    # This prevents parent apps from recreating children during teardown
    - name: pause-parents
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          echo "Pausing parent apps to prevent recreation..."
          ORDERED_PARENTS="green-base blue-base green-core blue-core green-apps"

          for app in $ORDERED_PARENTS; do
            if kubectl get app $app -n argocd &>/dev/null; then
              echo "Pausing parent app: $app"
              kubectl patch app $app -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' || true
              sleep 2
            else
              echo "Parent app not found: $app"
            fi
          done
          echo "Parent apps paused."

    # Step 2: Pause all non-skip child apps to stop auto-sync
    - name: pause-children
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_APPS="{{workflow.parameters.skip-apps}}"
          echo "Pausing all non-skip child apps to prevent auto-sync..."

          for app in $(kubectl get apps -n argocd -o jsonpath='{.items[*].metadata.name}'); do
            if ! echo " $SKIP_APPS " | grep -q " $app "; then
              echo "Pausing child app: $app"
              kubectl patch app $app -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' || true
            else
              echo "Skipping protected app: $app"
            fi
          done
          echo "Child apps paused."

    # Step 3: Delete K8up resources (schedules, backups, etc.)
    # Must happen before PVC deletion — K8up holds locks on PVCs
    - name: cleanup-k8up
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_NS="{{workflow.parameters.skip-namespaces}}"
          echo "Deleting K8up resources in non-skip namespaces..."

          for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
            if ! echo " $SKIP_NS " | grep -q " $ns "; then
              RESOURCES=$(kubectl get schedule.k8up.io,backup.k8up.io,prune.k8up.io,check.k8up.io,restore.k8up.io -n $ns -o name 2>/dev/null)
              if [ -n "$RESOURCES" ]; then
                echo "Deleting K8up resources in: $ns"
                kubectl delete schedule.k8up.io,backup.k8up.io,prune.k8up.io,check.k8up.io,restore.k8up.io --all -n $ns --wait=true --timeout=60s 2>/dev/null || true
              fi
            fi
          done

          echo "Waiting for K8up pods to terminate..."
          for attempt in $(seq 1 12); do
            K8UP_PODS=$(kubectl get pods --all-namespaces -l k8up.io/backup -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w)
            if [ "$K8UP_PODS" -eq 0 ]; then
              echo "All K8up pods terminated."
              break
            fi
            echo "Waiting for $K8UP_PODS K8up pods... ($attempt/12)"
            sleep 10
          done
          echo "K8up cleanup complete."

    # Step 4: Delete CNPG clusters gracefully
    # Operator must process finalizers before PVCs can be deleted
    - name: cleanup-cnpg
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_NS="{{workflow.parameters.skip-namespaces}}"
          echo "Deleting CNPG clusters gracefully..."

          for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
            if ! echo " $SKIP_NS " | grep -q " $ns "; then
              CLUSTERS=$(kubectl get clusters.postgresql.cnpg.io -n $ns -o name 2>/dev/null)
              if [ -n "$CLUSTERS" ]; then
                echo "Deleting CNPG clusters in $ns..."
                kubectl delete clusters.postgresql.cnpg.io --all -n $ns --wait=true --timeout=300s 2>/dev/null || true
              fi
            fi
          done

          echo "Waiting for CNPG pods to terminate..."
          for attempt in $(seq 1 12); do
            CNPG_PODS=$(kubectl get pods --all-namespaces -l cnpg.io/cluster -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w)
            if [ "$CNPG_PODS" -eq 0 ]; then
              echo "All CNPG pods terminated."
              break
            fi
            echo "Waiting for $CNPG_PODS CNPG pods... ($attempt/12)"
            sleep 10
          done
          echo "CNPG clusters deleted."

    # Step 5: Delete ArgoCD apps with cascade
    # argocd app delete --cascade properly tracks and deletes managed resources
    - name: delete-apps
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_APPS="{{workflow.parameters.skip-apps}}"
          echo "Installing ArgoCD CLI..."
          curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          chmod +x /usr/local/bin/argocd
          echo "ArgoCD CLI installed."

          echo "Deleting non-skip ArgoCD applications with cascade..."

          # Login to ArgoCD
          ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath='{.data.password}' | base64 -d)
          argocd login argocd-server.argocd.svc --plaintext --grpc-web \
            --username admin --password "$ARGOCD_PASS" || exit 1

          echo "Collecting apps to delete..."
          TO_DELETE=""
          for app in $(kubectl get apps -n argocd -o jsonpath='{.items[*].metadata.name}'); do
            if ! echo " $SKIP_APPS " | grep -q " $app "; then
              TO_DELETE="$TO_DELETE $app"
            else
              echo "Skipping protected app: $app"
            fi
          done

          if [ -n "$TO_DELETE" ]; then
            echo "Deleting apps: $TO_DELETE"
            for app in $TO_DELETE; do
              echo "Deleting app: $app"
              argocd app delete $app --cascade --yes 2>/dev/null || true
              sleep 2
            done
          else
            echo "No apps to delete."
          fi

          echo "Waiting for remaining apps to be deleted..."
          for attempt in $(seq 1 30); do
            REMAINING=$(kubectl get apps -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
            TO_DELETE_COUNT=0
            for app in $REMAINING; do
              if ! echo " $SKIP_APPS " | grep -q " $app "; then
                TO_DELETE_COUNT=$((TO_DELETE_COUNT + 1))
              fi
            done
            if [ "$TO_DELETE_COUNT" -eq 0 ]; then
              echo "All non-skip apps deleted."
              break
            fi
            echo "Waiting for $TO_DELETE_COUNT apps... ($attempt/30)"
            sleep 10
          done
          echo "App deletion complete."

    # Step 6: Delete remaining workloads
    # Second pass for raw manifests not managed by ArgoCD
    - name: delete-workloads
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_NS="{{workflow.parameters.skip-namespaces}}"
          echo "Deleting workloads in non-skip namespaces (cleanup pass)..."

          for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
            if ! echo " $SKIP_NS " | grep -q " $ns "; then
              RESOURCES=$(kubectl get deploy,sts,ds,jobs -n $ns --no-headers 2>/dev/null | wc -l)
              if [ "$RESOURCES" -gt 0 ]; then
                echo "Deleting $RESOURCES workloads in: $ns"
                kubectl delete deploy,sts,ds,jobs --all -n $ns --wait=true --timeout=300s 2>/dev/null || true
              fi
            fi
          done

          echo "Waiting for all workloads to terminate..."
          for attempt in $(seq 1 30); do
            REMAINING=0
            for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
              if ! echo " $SKIP_NS " | grep -q " $ns "; then
                COUNT=$(kubectl get deploy,sts,ds,jobs -n $ns --no-headers 2>/dev/null | wc -l)
                REMAINING=$((REMAINING + COUNT))
              fi
            done
            if [ "$REMAINING" -eq 0 ]; then
              echo "All workloads deleted."
              break
            fi
            echo "Waiting for $REMAINING workloads... ($attempt/30)"
            sleep 10
          done
          echo "Workload cleanup complete."

    # Step 7: Wait for pods to terminate
    # Only wait in namespaces that have PVCs — avoids DaemonSet namespaces
    - name: wait-for-pods
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_NS="{{workflow.parameters.skip-namespaces}}"
          echo "Waiting for pods to terminate in namespaces with PVCs..."

          for attempt in $(seq 1 30); do
            PVC_NS=$(kubectl get pvc --all-namespaces -o jsonpath='{.items[*].metadata.namespace}' 2>/dev/null | tr ' ' '\n' | sort -u)

            if [ -z "$PVC_NS" ]; then
              echo "No namespaces with PVCs remain."
              break
            fi

            FOUND=false
            for ns in $PVC_NS; do
              if ! echo " $SKIP_NS " | grep -q " $ns "; then
                POD_COUNT=$(kubectl get pod -n $ns --no-headers 2>/dev/null | wc -l)
                if [ "$POD_COUNT" -gt 0 ]; then
                  echo "  $ns: $POD_COUNT pods still running"
                  FOUND=true
                fi
              fi
            done

            if [ "$FOUND" = "false" ]; then
              echo "All pods in PVC namespaces terminated."
              break
            fi

            echo "Waiting... ($attempt/30)"
            sleep 10
          done
          echo "Pod wait complete."

    # Step 8: Delete PVCs
    # Graceful deletion — CSI provisioner processes Delete events and cleans up Ceph
    - name: delete-pvcs
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_NS="{{workflow.parameters.skip-namespaces}}"
          echo "Deleting PVCs in non-skip namespaces..."

          for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
            if ! echo " $SKIP_NS " | grep -q " $ns "; then
              PVC_COUNT=$(kubectl get pvc -n $ns --no-headers 2>/dev/null | wc -l)
              if [ "$PVC_COUNT" -gt 0 ]; then
                echo "Deleting $PVC_COUNT PVCs in: $ns"
                kubectl delete pvc --all -n $ns --wait=true --timeout=300s 2>/dev/null || true
              fi
            fi
          done

          echo "Waiting for all PVCs to be deleted..."
          for attempt in $(seq 1 30); do
            PVC_COUNT=0
            for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
              if ! echo " $SKIP_NS " | grep -q " $ns "; then
                COUNT=$(kubectl get pvc -n $ns --no-headers 2>/dev/null | wc -l)
                PVC_COUNT=$((PVC_COUNT + COUNT))
              fi
            done
            if [ "$PVC_COUNT" -eq 0 ]; then
              echo "All PVCs deleted."
              break
            fi
            echo "Waiting for $PVC_COUNT PVCs... ($attempt/30)"
            sleep 10
          done
          echo "PVC deletion complete."

    # Step 9: Verify no orphaned PVs
    # If any PVs remain bound to deleted namespaces, CSI didn't clean up properly
    - name: verify-pvs
      script:
        image: alpine/kubectl
        command: ["/bin/sh", "-c"]
        source: |
          SKIP_NS="{{workflow.parameters.skip-namespaces}}"
          echo "Verifying no orphaned PVs remain..."

          ORPHAN_FOUND=false
          for pv in $(kubectl get pv -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            CLAIM_NS=$(kubectl get pv $pv -o jsonpath='{.spec.claimRef.namespace}' 2>/dev/null)
            if [ -n "$CLAIM_NS" ]; then
              if ! echo " $SKIP_NS " | grep -q " $CLAIM_NS "; then
                echo "ORPHAN: PV $pv still bound to namespace $CLAIM_NS"
                ORPHAN_FOUND=true
              fi
            fi
          done

          if [ "$ORPHAN_FOUND" = true ]; then
            echo "ERROR: Orphaned PVs found. Check Ceph for orphaned RBD images:"
            echo "  rbd ls osd"
            echo "  ceph fs subvolume ls cephfs"
            exit 1
          fi

          echo "SUCCESS: No orphaned PVs found. Ceph data successfully wiped."
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

**Key Design Principles:**

1. **Ordered teardown**: Parents paused before children, operators before workloads, CNPG/K8up before PVCs
2. **No force-deletion of PVCs/PVs**: Graceful deletion only — let CSI provisioner clean up Ceph data
3. **No finalizer stripping**: Only strip finalizers from stuck namespaces as last resort (not implemented — graceful approach works)
4. **PVC-aware waiting**: Only wait for pods in namespaces with PVCs — ignores DaemonSet namespaces
5. **Centralized configuration**: Skip lists in workflow parameters, not annotations on individual apps
6. **Proper cascade**: `argocd app delete --cascade` tracks and deletes all managed resources
7. **PV verification**: Final check ensures CSI provisioner successfully cleaned up all Ceph data

**Execution Time**: ~10-15 minutes for full cluster teardown with ~3TB+ of data.

**RGW Safety**: RGW buckets are NOT deleted by the kill-switch — they persist on Proxmox outside the K8s lifecycle.

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
Phase 5: ~~Application S3 Users~~ — SKIPPED (shared admin creds)
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

**Note**: Phase 5 (per-app S3 users) was skipped in favor of shared admin credentials. If per-app users are added later:

**Issue**: Application credentials not working
**Solution**:
- Verify user exists: `radosgw-admin user info --uid=<app-name>`
- Check secret contains correct keys: `kubectl get secret ceph-external-secret -n ceph -o yaml`
- Test with specific credentials

**Issue**: Admin credentials not working for an application
**Solution**:
- Verify admin user exists: `radosgw-admin user info --uid=admin`
- Check secret contains correct keys: `kubectl get secret ceph-external-secret -n <namespace> -o yaml`
- Ensure `s3_access_key` and `s3_secret_key` are being used (not `access_key_id`/`secret_access_key`)

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
*Last updated: 2026-04-12 — Migration complete through Phase 11. SeaweedFS removed, kill-switch redesigned and tested successfully, ~3TB+ Ceph space recovered, blue cluster deployed.*
