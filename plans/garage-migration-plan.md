# Garage Migration Plan: TrueNAS → NixOS VM on Japan

## Objective
Decommission the TrueNAS VM (currently on Proxmox node `method`) and migrate its three physical SSDs (2x 2TB, 1x 1TB) to a new NixOS VM running Garage on the Proxmox node `japan`. The new VM will replace TrueNAS/MinIO as the **backup target** for the green cluster. **Ceph RGW is not being replaced** and will remain the primary S3 endpoint for cluster workloads.

## Target Architecture
- **Hostname:** `garage`
- **IP:** `10.0.20.21` (VLAN 20)
- **Gateway:** `10.0.20.2`
- **Node:** `japan`
- **IaC Pipeline:** OpenTofu (`tofu/proxmox/garage`) → Cloud-Init → Colmena (`nix/hosts/garage`)
- **Storage:** Garage multi-HDD with zero replication (`replication_factor = 1`)
- **K8s Exposure:** New `external-garage` Service/Endpoint in the `garage` namespace
- **Secrets:** Managed via External Secrets Operator + Vault

---

## Phase 0: Discovery & Pre-Requisites
**STATUS: COMPLETE** (secrets deferred until after VM is stable)

### Hardware Discovered
- **HBA PCIe ID:** `1000:0097` (Broadcom / LSI SAS3008) on IOMMU group 16
- **Disk `/dev/disk/by-id/` paths:**
  | Disk | by-id | Size |
  |---|---|---|
  | 1 | `ata-PNY_CS900_2TB_SSD_PNY225122122301009C8` | 2TB |
  | 2 | `ata-PNY_CS900_2TB_SSD_PNY225122122301009CB` | 2TB |
  | 3 | `ata-CT1000BX500SSD1_2308E6B0E700` | 1TB |

### Secrets to Generate (Deferred to Phase 5)
Add to `vault_secrets.core.garage` in `secrets.enc.json`:
- `s3_access_key` / `s3_secret_key` (generated via `garage-manage key create`)
- `rpc_secret` (`openssl rand -hex 32`)
- `admin_token`

---

## Phase 1: Ansible — Enable PCIe Passthrough on Japan
**STATUS: COMPLETE**

Applied passthrough config to `ansible/inventory/host_vars/japan.yml`, ran the playbook, rebooted, and verified `vfio_pci` claimed the HBA (`0000:03:00.0`).

---

## Phase 3: Raw Image Build + VM Provisioning
**STATUS: COMPLETE**

The original template/clone approach was abandoned after multiple failures (disk interface mismatches, cross-node storage migration, EFI config issues). The **raw image direct-download** approach proved simpler and more reliable.

### Key Files
- **`nix/hosts/proxmox-image/default.nix`** — Generic image config (GRUB EFI `nodev`, `networkd`, `virtio_scsi`/`sd_mod` initrd, cloud-init, qemu-guest-agent)
- **`nix/hosts/proxmox-image/img-build.nix`** — `make-disk-image.nix` invocation producing a raw EFI image
- **`flake.nix`** — `proxmox-image` nixosConfiguration
- **`tofu/proxmox/garage/main.tf`** — VM definition using `data.proxmox_file` to reference `nixos.img` from Proxmox storage (cephfs)

### Image Staging
The image was built and copied to Proxmox's `cephfs` datastore:
```bash
nix build .#nixosConfigurations.proxmox-image.config.system.build.image
# Image placed on Proxmox node at /var/lib/vz/template/iso/nixos.img
```

---

## Phase 4: Colmena — NixOS Configuration
**STATUS: COMPLETE**

Deployed a minimal NixOS config (no Garage, no secrets) to verify Colmena connectivity before layering in Garage.

### Files Created
- **`nix/hosts/garage/default.nix`** — Colmena host config (`targetHost: 10.0.20.21`, static networking on `eth0`)
- **`nix/hosts/garage/hardware-configuration.nix`** — Generated on the VM via `nixos-generate-config`

### Fixes Applied
1. **`default.nix` must be a plain attrset, not a function** — Colmena auto-discovery (`lib/generators.nix`) checks `hostModule ? "deploy"`; a function has no such attribute, so the host is silently skipped.
2. **Bootloader override** — `profiles/server.nix` pulls in `modules/core/boot.nix` which enables `systemd-boot` by default. The VM was provisioned with GRUB, so `garage/default.nix` must override:
   ```nix
   boot.loader.systemd-boot.enable = false;
   boot.loader.efi.canTouchEfiVariables = false;
   boot.loader.grub = { enable = true; device = "nodev"; efiSupport = true; efiInstallAsRemovable = true; };
   ```
3. **`canTouchEfiVariables = false`** is required when using `efiInstallAsRemovable` (NixOS assertion).

### Deploy
```bash
colmena apply --on garage --impure
```

---

## Phase 5: NixOS Garage Module Setup

Garage is configured declaratively via the NixOS `services.garage` module. Disks are formatted once via disko (manual apply). Secrets are injected via sops-nix templates and `environmentFile`.

### 5.1 Pre-Deploy: Generate Static Secrets

Run locally and add to `secrets.enc.json` under `vault_secrets.core.garage`:
```bash
# RPC secret (hex, 32 bytes)
openssl rand -hex 32

# Admin token (base64, 32 bytes)
openssl rand -base64 32
```

Structure in `secrets.enc.json`:
```json
"garage": {
  "rpc_secret": "<hex-output>",
  "admin_token": "<base64-output>",
  "s3_access_key": "",
  "s3_secret_key": ""
}
```

### 5.2 Files Created / Modified

#### `nix/hosts/garage/disko.nix` (NEW)

Declares the three SSDs as XFS filesystems mounted at `/mnt/garage/disk{1,2,3}`:

```nix
{ inputs, ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      garage-data-1 = {
        device = "/dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009C8";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/mnt/garage/disk1";
              };
            };
          };
        };
      };
      garage-data-2 = {
        device = "/dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009CB";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/mnt/garage/disk2";
              };
            };
          };
        };
      };
      garage-data-3 = {
        device = "/dev/disk/by-id/ata-CT1000BX500SSD1_2308E6B0E700";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/mnt/garage/disk3";
              };
            };
          };
        };
      };
    };
  };
}
```

#### `nix/hosts/garage/default.nix` (MODIFIED)

```nix
{ config, pkgs, lib, ... }:
{
  system = "x86_64-linux";

  deploy = {
    tags = [ "garage" "server" ];
    targetHost = "10.0.20.21";
  };

  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./../../profiles/server.nix
  ];

  cfg = {
    networking = {
      static = {
        interface = "eth0";
        address = "10.0.20.21";
        gateway = "10.0.20.2";
        nameservers = [ "10.0.9.2" ];
      };
    };
  };

  # Hand off network control from cloud-init to NixOS networkd
  services.cloud-init.network.enable = false;

  # Keep GRUB to avoid bootloader conflicts
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Enable periodic TRIM for consumer SSD longevity
  services.fstrim.enable = true;

  # Garage S3 Object Storage
  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    environmentFile = config.sops.templates."garage-env".path;

    settings = {
      replication_factor = 1;
      # metadata_dir omitted -- defaults to /var/lib/garage/meta on NVMe root disk
      data_dir = [
        { path = "/mnt/garage/disk1"; capacity = "2T"; }
        { path = "/mnt/garage/disk2"; capacity = "2T"; }
        { path = "/mnt/garage/disk3"; capacity = "1T"; }
      ];
      # Single-node: bind RPC to localhost only
      rpc_bind_addr = "127.0.0.1:3901";
      s3_api = {
        api_bind_addr = "[::]:3900";
        s3_region = "garage";
      };
      admin = {
        api_bind_addr = "127.0.0.1:3903";
      };
    };
  };

  # Sops secrets for garage
  sops.secrets.garage_rpc_secret = {
    key = "vault_secrets/core/garage/rpc_secret";
    mode = "0400";
  };

  sops.secrets.garage_admin_token = {
    key = "vault_secrets/core/garage/admin_token";
    mode = "0400";
  };

  # Environment file template for garage service
  # Garage supports GARAGE_*_FILE env vars since v0.8.5/v0.9.1
  sops.templates."garage-env".content = ''
    GARAGE_RPC_SECRET_FILE=${config.sops.secrets.garage_rpc_secret.path}
    GARAGE_ADMIN_TOKEN_FILE=${config.sops.secrets.garage_admin_token.path}
  '';

  # Open firewall for S3 API only (RPC and admin are localhost-only)
  networking.firewall.allowedTCPPorts = [ 3900 ];
}
```

**Notes:**
- **DynamicUser / Permissions:** The NixOS `services.garage` module sets `DynamicUser = true` by default, but it automatically adds non-default data directories to `ReadWritePaths`. This allows the service to write to `/mnt/garage/disk*` without manual permission management.
- **Admin API:** Bound to `127.0.0.1`. Use `ssh -L 3903:localhost:3903 garage` for admin operations.
- **TRIM:** `services.fstrim.enable = true` is enabled since these are consumer SSDs without DRAM caches.

### 5.3 Deploy

```bash
colmena apply --on garage --impure
```

### 5.4 Format Disks with Disko (One-Time, Manual)

**Do not automate this.** Run once after the NixOS config is deployed and the `disko.nix` module is in place:

```bash
ssh -p 4185 bhamm@10.0.20.21
sudo nix run github:nix-community/disko -- --mode disko /etc/nixos/disko.nix
```

This will partition and format all three SSDs as XFS and mount them at `/mnt/garage/disk{1,2,3}`. Verify:

```bash
mount | grep garage
lsblk
```

### 5.5 Verify Garage Service

```bash
ssh -p 4185 bhamm@10.0.20.21
sudo systemctl status garage
sudo garage node id
```

### 5.6 Create Layout, Bucket, and Key (Manual)

```bash
# 1. Get node ID
sudo garage node id

# 2. Assign node to zone
sudo garage zone assign <NODE_ID> japan --capacity 5T

# 3. Create the bucket
sudo garage bucket create ceph-rgw

# 4. Create the access key
sudo garage key create garage-key
```

### 5.7 Sync S3 Keys to Secrets

Add the generated `access_key_id` and `secret_access_key` to `secrets.enc.json`:
```json
"vault_secrets": {
  "core": {
    "garage": {
      "rpc_secret": "...",
      "admin_token": "...",
      "s3_access_key": "<generated>",
      "s3_secret_key": "<generated>"
    }
  }
}
```
Re-encrypt and commit.

---

## Phase 5.x: Monitoring & Observability (Post-Deploy)

> **Note:** Not a blocker for initial deployment, but should be added shortly after cutover.

Garage exposes Prometheus metrics at `http://127.0.0.1:3903/metrics` (requires `metrics_token` if configured). Recommended monitoring:

- **Disk space:** Alert when `/mnt/garage/disk*` exceeds 85% capacity
- **SMART health:** Install `smartmontools` and schedule periodic `smartctl` checks on the physical SSDs
- **Service health:** Monitor `systemctl status garage` and alert on failure
- **Backup job failures:** The Argo CronWorkflow can emit metrics; alert if the backup fails
- **Garage-specific metrics:** `garage_api_request_duration_seconds`, `garage_block_manager_storage_used_bytes`

Quick SMART check (add to a systemd timer or cron):
```bash
sudo smartctl -H /dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009C8
sudo smartctl -H /dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009CB
sudo smartctl -H /dev/disk/by-id/ata-CT1000BX500SSD1_2308E6B0E700
```

---

## Phase 6: Kubernetes Manifests

### 6.1 New Directory: `kubernetes/manifests/base/garage/`

#### `kubernetes/manifests/base/garage/ns-all.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: garage
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

#### `kubernetes/manifests/base/garage/endpoints-all.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-garage
  namespace: garage
  annotations:
    argocd.argoproj.io/sync-wave: "7"
spec:
  ports:
    - name: s3
      port: 80
      targetPort: 3900
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: external-garage
  namespace: garage
  annotations:
    argocd.argoproj.io/sync-wave: "7"
subsets:
  - addresses:
      - ip: 10.0.20.21
    ports:
      - name: s3
        port: 3900
        protocol: TCP
```

#### `kubernetes/manifests/base/garage/external-secret-all.yaml`
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: garage-external-secret
  namespace: garage
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  refreshInterval: "1h"
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: garage-external-secret
    creationPolicy: Owner
  data:
    - secretKey: s3_access_key
      remoteRef:
        key: vault_secrets/core/garage
        property: s3_access_key
    - secretKey: s3_secret_key
      remoteRef:
        key: vault_secrets/core/garage
        property: s3_secret_key
```

### 6.2 Update Core-Green Application

Ensure `core-green.yaml` (or the relevant ArgoCD ApplicationSet) includes the new `garage/` directory in its source path list so ArgoCD syncs it.

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
- [ ] Phase 0: Generate Garage `rpc_secret` and `admin_token`, add to `secrets.enc.json`
- [x] Phase 1: Update `ansible/inventory/host_vars/japan.yml` with passthrough vars
- [x] Phase 1: Run Ansible on `japan` and reboot
- [x] Phase 2: Migrate physical SSDs from `method` to `japan`
- [x] Phase 3: Build raw NixOS image, stage on Proxmox, provision VM via OpenTofu
- [x] Phase 3: Verify VM boots, cloud-init applies network, SSH works
- [x] Phase 4: Create `nix/hosts/garage/` configuration
- [x] Phase 4: Deploy with `colmena apply --on garage`
- [ ] Phase 5: Create `nix/hosts/garage/disko.nix` with XFS disks
- [ ] Phase 5: Update `nix/hosts/garage/default.nix` with `services.garage` module
- [ ] Phase 5: Deploy updated config with `colmena apply --on garage --impure`
- [ ] Phase 5: Run disko manually to format and mount disks
- [ ] Phase 5: Run `garage` CLI to assign zone, create bucket and key
- [ ] Phase 5: Update `secrets.enc.json` with generated Garage S3 credentials
- [ ] Phase 6: Create `kubernetes/manifests/base/garage/` manifests
- [ ] Phase 6: Update ArgoCD `core-green.yaml` to include garage manifests
- [ ] Phase 7: Update `buckets-green.yaml` with R2→Garage restore template
- [ ] Phase 7: Trigger the restore workflow and verify
- [ ] Phase 8: Update `ceph-rgw-backup-green.yaml` to sync rgw → garage → r2/b2
- [ ] Phase 8: Verify backup CronJob runs successfully
- [ ] Phase 8: Destroy TrueNAS VM
