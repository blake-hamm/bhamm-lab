# Garage Migration Plan: TrueNAS → NixOS VM on Japan

## Objective
Decommission the TrueNAS VM and migrate its three physical SSDs (2x 2TB, 1x 1TB) to a new NixOS VM running Garage on Proxmox node `japan`. Garage replaces TrueNAS/MinIO as the **backup target** for the green cluster. **Ceph RGW remains the primary S3 endpoint** for cluster workloads.

## Target Architecture
- **Hostname:** `garage`
- **IP:** `10.0.20.21` (VLAN 20)
- **Node:** `japan`
- **IaC Pipeline:** OpenTofu (`tofu/proxmox/garage`) → Cloud-Init → Colmena (`nix/hosts/garage`)
- **Storage:** Garage multi-HDD with zero replication (`replication_factor = 1`)
- **K8s Exposure:** `external-garage` Service/Endpoint in the `garage` namespace
- **Secrets:** Managed via External Secrets Operator + Vault

---

## Phase 0: Discovery & Pre-Requisites
**STATUS: COMPLETE**

- HBA PCIe ID discovered: `1000:0097` (Broadcom / LSI SAS3008) on IOMMU group 16
- Disk paths documented in `nix/hosts/garage/garage.nix`
- `rpc_secret` and `admin_token` generated and added to `vault_secrets.core.garage`

---

## Phase 1: Ansible — Enable PCIe Passthrough on Japan
**STATUS: COMPLETE**

Passthrough config applied to `ansible/inventory/host_vars/japan.yml`, playbook ran, rebooted, `vfio_pci` claimed the HBA.

---

## Phase 3: Raw Image Build + VM Provisioning
**STATUS: COMPLETE**

Raw image direct-download approach. VM provisioned via OpenTofu with HBA passthrough. Image built from `nix/hosts/proxmox-image/`.

---

## Phase 4: Colmena — NixOS Base Configuration
**STATUS: COMPLETE**

Minimal NixOS config deployed to verify connectivity. Key fixes: GRUB bootloader override, `canTouchEfiVariables = false`, plain attrset host config for Colmena auto-discovery.

---

## Phase 5: NixOS Garage Module Setup
**STATUS: COMPLETE**

Garage service deployed with 3 data disks, sops-nix secrets, `noauto`+`automount` mounts, dedicated `garage` user, and firewall on 3900.

**Full deployment steps documented in:** `docker/docs-site/docs/operations/garage.md`

**Key files:**
- `nix/hosts/garage/default.nix` — Host config
- `nix/hosts/garage/garage.nix` — Service, secrets, mounts
- `nix/hosts/garage/disko.nix` — Reference only (disk layout documentation)

**Post-deploy manual steps completed:**
- Disks partitioned and formatted as XFS
- Node assigned to `japan` zone with 5TB capacity
- Bucket `ceph-rgw` created
- Key `garage-key` created with RW access
- S3 credentials synced to `secrets.enc.json`

---

## Phase 6: Kubernetes Manifests
**STATUS: COMPLETE**

Garage namespace, external Service/Endpoints, and ExternalSecret deployed via the common Helm chart. Auto-synced by the existing `${environment}-base` ArgoCD Application — no manual ArgoCD registration needed.

**Key files:**
- `kubernetes/manifests/base/garage/ns-all.yaml` — Namespace
- `kubernetes/manifests/base/garage/endpoints-all.yaml` — Service + Endpoints (`10.0.20.21:3900`)
- `kubernetes/manifests/base/garage/common-green.yaml` — Common chart Application for ExternalSecret

---

## Phase 7: Data Sync — Restore from Cloudflare R2

Extend `kubernetes/manifests/base/ceph/buckets-green.yaml` with a new on-demand template to sync **R2 → Garage**.

### 7.1 Add to `buckets-green.yaml`
```yaml
    - name: restore-from-r2-to-garage
      steps:
        - - name: sync-r2-to-garage
            template: sync-r2-to-garage
        - - name: verify-garage
            template: verify-garage
    - name: sync-r2-to-garage
      container:
        image: rclone/rclone
        resources:
          requests:
            memory: 512Mi
          limits:
            memory: 4Gi
        env:
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
          - name: GARAGE_ACCESS_KEY_ID
            valueFrom:
              secretKeyRef:
                name: garage-external-secret
                key: s3_access_key
          - name: GARAGE_SECRET_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: garage-external-secret
                key: s3_secret_key
        command: ["/bin/sh", "-c"]
        args:
          - |
            set -ex
            rclone config create r2 s3 \
              provider Cloudflare \
              access_key_id $R2_ACCESS_KEY_ID \
              secret_access_key $R2_SECRET_ACCESS_KEY \
              endpoint $R2_ENDPOINT

            rclone config create garage s3 \
              provider Other \
              access_key_id $GARAGE_ACCESS_KEY_ID \
              secret_access_key $GARAGE_SECRET_ACCESS_KEY \
              endpoint http://external-garage.garage.svc.cluster.local:80

            echo "=== Syncing r2:ceph-rgw → garage:ceph-rgw ==="
            rclone sync r2:ceph-rgw garage:ceph-rgw \
              --progress \
              --fast-list \
              --checksum \
              --check-first \
              --transfers=16 \
              --checkers=32 \
              --s3-chunk-size=16M \
              --s3-upload-concurrency=8 \
              --s3-no-head \
              --s3-no-check-bucket \
              --disable-http2 \
              --max-backlog=10000 \
              --stats=30s
    - name: verify-garage
      container:
        image: rclone/rclone
        resources:
          requests:
            memory: 256Mi
          limits:
            memory: 1Gi
        env:
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
          - name: GARAGE_ACCESS_KEY_ID
            valueFrom:
              secretKeyRef:
                name: garage-external-secret
                key: s3_access_key
          - name: GARAGE_SECRET_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: garage-external-secret
                key: s3_secret_key
        command: ["/bin/sh", "-c"]
        args:
          - |
            rclone config create r2 s3 \
              provider Cloudflare \
              access_key_id $R2_ACCESS_KEY_ID \
              secret_access_key $R2_SECRET_ACCESS_KEY \
              endpoint $R2_ENDPOINT

            rclone config create garage s3 \
              provider Other \
              access_key_id $GARAGE_ACCESS_KEY_ID \
              secret_access_key $GARAGE_SECRET_ACCESS_KEY \
              endpoint http://external-garage.garage.svc.cluster.local:80

            echo "=== Verification: r2:ceph-rgw vs garage:ceph-rgw ==="
            rclone check r2:ceph-rgw garage:ceph-rgw --one-way --checksum
```

### 7.2 Trigger the Workflow

Once ArgoCD syncs the updated `ClusterWorkflowTemplate`, trigger it manually:
```bash
argo submit --from clusterworkflowtemplate/create-ceph-buckets-green \
  --entrypoint restore-from-r2-to-garage \
  -n ceph
```

---

## Phase 8: Cutover — Update Backup CronJob & Decommission TrueNAS

**Important:** This migration replaces the **TrueNAS/MinIO backup target**, not Ceph RGW. The existing `external-rgw` Service/Endpoint remains untouched.

The current `ceph-rgw-backup-green.yaml` workflow syncs:
```
rgw → minio → r2/b2
```
Since Garage replaces MinIO, the workflow should be updated to:
```
rgw → garage → r2/b2
```

### 8.1 Update `kubernetes/manifests/base/ceph/ceph-rgw-backup-green.yaml`

Modify the templates as follows:
- **`list-buckets`**: Keep as-is (lists buckets from `rgw`).
- **`rclone-sync-to-garage`** (replace `rclone-sync-to-minio`):
  - Source: `rgw` (`http://external-rgw.ceph.svc.cluster.local:80`)
  - Destination: `garage` (`http://external-garage.garage.svc.cluster.local:80`)
  - Sync each bucket into `garage:ceph-rgw/${bucket}`
  - Use `garage-external-secret` for Garage credentials
- **`rclone-sync-to-r2`**:
  - Change source from `minio:ceph-rgw` to `garage:ceph-rgw`
  - Keep R2 credentials from `ceph-external-secret`
- **`rclone-sync-to-b2`**:
  - Change source from `minio:ceph-rgw` to `garage:ceph-rgw`
  - Keep B2 credentials from `ceph-external-secret`

### 8.2 Decommission TrueNAS
1. Ensure the updated backup CronJob runs successfully at least once.
2. Verify data in Garage (`rclone check` passes).
3. Run `tofu destroy` in `tofu/proxmox/truenas/` (or manually delete VM 199).
4. Remove TrueNAS references from DNS, monitoring, and documentation.

---

## Execution Checklist

- [x] Phase 0: Discover HBA ID and disk `/dev/disk/by-id/` paths
- [x] Phase 0: Generate Garage `rpc_secret` and `admin_token`, add to `secrets.enc.json`
- [x] Phase 1: Update `ansible/inventory/host_vars/japan.yml` with passthrough vars
- [x] Phase 1: Run Ansible on `japan` and reboot
- [x] Phase 2: Migrate physical SSDs from `method` to `japan`
- [x] Phase 3: Build raw NixOS image, stage on Proxmox, provision VM via OpenTofu
- [x] Phase 3: Verify VM boots, cloud-init applies network, SSH works
- [x] Phase 4: Create `nix/hosts/garage/` configuration
- [x] Phase 4: Deploy with `colmena apply --on garage`
- [x] Phase 5: Create `nix/hosts/garage/garage.nix` with service config
- [x] Phase 5: Create `nix/hosts/garage/disko.nix` (reference only)
- [x] Phase 5: Deploy updated config with `colmena apply --on garage --impure`
- [x] Phase 5: Format and mount disks manually
- [x] Phase 5: Run `garage` CLI to assign zone, create bucket and key
- [x] Phase 5: Update `secrets.enc.json` with generated Garage S3 credentials
- [x] Phase 6: Create `kubernetes/manifests/base/garage/` manifests
- [ ] Phase 7: Update `buckets-green.yaml` with R2→Garage restore template
- [ ] Phase 7: Trigger the restore workflow and verify
- [ ] Phase 8: Update `ceph-rgw-backup-green.yaml` to sync rgw → garage → r2/b2
- [ ] Phase 8: Verify backup CronJob runs successfully
- [ ] Phase 8: Destroy TrueNAS VM
