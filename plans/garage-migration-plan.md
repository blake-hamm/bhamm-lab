# Garage Migration Plan: TrueNAS → NixOS VM on Japan

## Objective
Decommission the TrueNAS VM (currently on Proxmox node `method`) and migrate its three physical SSDs (2x 2TB, 1x 1TB) to a new NixOS VM running Garage on the Proxmox node `japan`. The new VM will replace TrueNAS/MinIO as the **backup target** for the green cluster. **Ceph RGW is not being replaced** and will remain the primary S3 endpoint for cluster workloads.

## Target Architecture
- **Hostname:** `garage`
- **IP:** `10.0.20.21` (VLAN 20)
- **Node:** `japan`
- **IaC Pipeline:** OpenTofu (`tofu/proxmox/garage`) → Cloud-Init → Colmena (`nix/hosts/garage`)
- **Storage:** Garage multi-HDD with zero replication (`replication_factor = 1`)
- **K8s Exposure:** New `external-garage` Service/Endpoint in the `garage` namespace
- **Secrets:** Managed via External Secrets Operator + Vault

---

## Phase 0: Discovery & Pre-Requisites
**STATUS: COMPLETE** (secrets deferred until after VM is stable)

### 0.1 Discover HBA PCIe ID
Discovered on `japan`:
```
03:00.0 Serial Attached SCSI controller [0107]: Broadcom / LSI SAS3008 PCI-Express Fusion-MPT SAS-3 [1000:0097] (rev 02)
```
**Vendor:device ID for Ansible:** `1000:0097`

### 0.2 Discover Disk `/dev/disk/by-id/` Paths
Discovered on `japan`:
| Disk | by-id | Size |
|---|---|---|
| 1 | `ata-PNY_CS900_2TB_SSD_PNY225122122301009C8` | 2TB |
| 2 | `ata-PNY_CS900_2TB_SSD_PNY225122122301009CB` | 2TB |
| 3 | `ata-CT1000BX500SSD1_2308E6B0E700` | 1TB |

### 0.3 Secrets to Generate
**DEFERRED** — The following secrets will be added to `secrets.enc.json` (under `vault_secrets.core.garage`) after the VM is installed:
- `GARAGE_ACCESS_KEY_ID`
- `GARAGE_SECRET_ACCESS_KEY`
- `GARAGE_ADMIN_TOKEN`
- `GARAGE_RPC_SECRET` (32-byte hex, e.g. `openssl rand -hex 32`)

---

## Phase 1: Ansible — Enable PCIe Passthrough on Japan
**STATUS: COMPLETE**

### 1.1 Modify `ansible/inventory/host_vars/japan.yml`
Added:
```yaml
pve_pcie_passthrough_enabled: true
pve_iommu_passthrough_mode: true
pve_iommu_unsafe_interrupts: false
pve_pcie_ovmf_enabled: false
pve_pci_device_ids:
  - id: "1000:0097"  # Broadcom / LSI SAS3008
pve_vfio_blacklist_drivers:
  - name: "mpt3sas"
```

### 1.2 Run Ansible
```bash
ansible-playbook -i ansible/inventory/hosts ansible/debian.yml --limit japan
```

### 1.3 Reboot Japan
```bash
ssh root@10.0.20.15 -p 4185 reboot
```
**Verified after reboot:**
- `dmesg | grep -i vfio` shows `vfio_pci: add [1000:0097...]`
- IOMMU group 16 contains `0000:03:00.0`

---

## Phase 2: Physical Migration
**STATUS: COMPLETE**

1. **Power off the TrueNAS VM** (VM ID 199 on `method`).
2. **Physically remove** the three SSDs from the `method` backplane.
3. **Install** the three SSDs into the backplane of `japan`.
4. **Verified disk visibility** on `japan`:
   ```bash
   ls -l /dev/disk/by-id/
   ```
   Disks are visible as `sda`, `sdb`, `sdc` (plus existing Ceph OSDs).

---

## Phase 3: Build Generic NixOS Proxmox Image + Provision VM
**STATUS: REVISED** — The initial approach (NixOS minimal ISO + cloud-init) failed because the ISO does not support cloud-init. The new approach is to build a generic, reusable NixOS Proxmox image with cloud-init baked in, upload it to the cluster, and reference it from OpenTofu.

> **Lessons learned during implementation:**
> 1. `bios = "ovmf"` + an `efi_disk` block is required (the plan originally had `"seabios"`, which cannot boot a GPT disk with an ESP partition).
> 2. The provider `endpoint` must point to `method` (`10.0.20.11`) rather than `japan` because `root@pam` password auth works on `method` but returns 401 on `japan`. Proxmox cluster API proxying handles the cross-node operations transparently.
> 3. NixOS does **not** publish official QCOW2/cloud images on `channels.nixos.org`. The canonical approach for Proxmox is to build a native `.vma.zst` image.
> 4. Cloud-init works correctly inside a NixOS guest when `services.cloud-init.enable = true` is configured in the image.

### 3.1 Build the Generic NixOS Proxmox Image

Create a reusable, generic NixOS image for Proxmox. This image is **not** garage-specific; it can be reused for future NixOS VMs.

#### `nix/hosts/proxmox-image/default.nix`
```nix
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/virtualisation/proxmox-image.nix")
  ];

  # Boot support
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  # Cloud-init for Proxmox metadata (IP, SSH keys, hostname)
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # QEMU guest agent for Proxmox integrations
  services.qemuGuest.enable = true;

  # SSH must be enabled for Colmena / remote access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkDefault "prohibit-password";
  };

  # Create the default user that cloud-init will inject keys for
  users.users.bhamm = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      # Keys will be injected by Proxmox cloud-init; these are fallbacks
    ];
  };

  # Allow sudo without password for wheel during initial bootstrap
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  system.stateVersion = "25.11";
}
```

#### `flake.nix` addition
Add a new `nixosConfigurations` entry for the generic Proxmox image:
```nix
proxmox-image = nixpkgs.lib.nixosSystem {
  system = shared.system;
  modules = [
    (import ./nix/hosts/proxmox-image)
  ];
  specialArgs = {
    host = "proxmox-image";
    inherit self inputs shared;
    inherit pkgs-unstable;
  };
};
```

#### Build the image
```bash
nixos-rebuild build-image --image-variant proxmox --flake .#proxmox-image
```

> **Fallback:** If `build-image --image-variant proxmox` is not available in nixpkgs 25.11, use `nixos-generators`:
> ```bash
> nix run github:nix-community/nixos-generators -- --format proxmox -c ./nix/hosts/proxmox-image/default.nix
> ```

The build produces a file like `vzdump-qemu-proxmox-image-*.vma.zst` in the result directory (often `./result/` or `/nix/store/...`).

#### Upload to Proxmox
Copy the `.vma.zst` file to `method` (or any node with the target datastore), then restore it as a template:
```bash
scp /nix/store/...-vzdump-qemu-proxmox-image-*.vma.zst root@10.0.20.11:/var/lib/vz/dump/
ssh root@10.0.20.11 "qmrestore /var/lib/vz/dump/vzdump-qemu-proxmox-image-*.vma.zst 9000 --unique true"
# Optional: convert VM 9000 to a template
ssh root@10.0.20.11 "qm template 9000"
```
Note the resulting virtual disk path (e.g., `lvm:vm-9000-disk-0`) — this is what OpenTofu will reference.

### 3.2 OpenTofu VM Configuration (using the pre-built image)

Create `tofu/proxmox/garage/` with the following files.

#### `tofu/proxmox/garage/main.tf`
```hcl
provider "proxmox" {
  endpoint = var.proxmox_url
  insecure = true
  ssh {
    agent    = true
    username = "root"
    node {
      name    = "japan"
      address = "10.0.20.15"
      port    = "4185"
    }
  }
}

resource "proxmox_virtual_environment_vm" "garage" {
  name          = "garage"
  node_name     = var.node_name
  vm_id         = var.vm_id
  tags          = ["tofu", "garage", "nixos"]
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "ovmf"

  started         = true
  on_boot         = true
  stop_on_destroy = true

  agent {
    enabled = true
    trim    = true
    type    = "virtio"
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
    floating  = 0
  }

  network_device {
    model  = "virtio"
    bridge = var.net_bridge
    trunks = var.net_trunks
    mtu    = var.net_mtu
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id = var.datastore_boot
    type         = "4m"
  }

  disk {
    datastore_id = var.datastore_boot
    file_id      = var.proxmox_image_file_id
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    size         = var.boot_size
  }

  # HBA PCIe passthrough
  dynamic "hostpci" {
    for_each = var.hba_pcie_ids
    content {
      device = "hostpci${hostpci.key}"
      id     = hostpci.value
      pcie   = true
      rombar = true
    }
  }

  # Cloud-Init
  initialization {
    datastore_id = var.datastore_boot
    ip_config {
      ipv4 {
        address = "${var.garage_ip}/24"
        gateway = "10.0.20.1"
      }
    }
    dns {
      domain  = ""
      servers = ["10.0.9.2"]
    }
    user_account {
      username = var.initial_user
      keys     = var.ssh_keys
    }
  }
}
```

#### `tofu/proxmox/garage/variables.tf`
```hcl
variable "proxmox_url" {
  default = "https://10.0.20.11:8006" # Use method for API auth; cluster proxies to japan
  type    = string
}

variable "node_name" {
  default = "japan"
  type    = string
}

variable "proxmox_image_file_id" {
  description = "File ID of the pre-built NixOS Proxmox image (e.g. lvm:vm-9000-disk-0)"
  type        = string
}

variable "vm_id" {
  default = 200
  type    = number
}

variable "boot_size" {
  default = 20
  type    = number
}

variable "cpu_cores" {
  default = 4
  type    = number
}

variable "memory" {
  default = 10240
  type    = number
}

variable "net_bridge" {
  default = "vmbr0"
  type    = string
}

variable "net_trunks" {
  default = "1;20;30"
  type    = string
}

variable "net_mtu" {
  default = 9000
  type    = number
}

variable "datastore_boot" {
  default = "lvm"
  type    = string
}

variable "garage_ip" {
  default = "10.0.20.21"
  type    = string
}

variable "hba_pcie_ids" {
  description = "PCIe slot addresses for the HBA controller"
  type        = list(string)
  default     = ["0000:03:00.0"] # Discovered in Phase 0
}

variable "initial_user" {
  description = "Username for cloud-init injection"
  default     = "bhamm"
  type        = string
}

variable "ssh_keys" {
  type    = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn6e5VeOkY4WcW0wPmz8uWj+yd+kulj7Ls7upTdKFUO gitea@bhamm-lab.com"
  ]
}
```

#### `tofu/proxmox/garage/providers.tf`
```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.73.0"
    }
  }
}
```

#### `tofu/proxmox/garage/backend.tf`
```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

### 3.3 Apply OpenTofu
After the image is uploaded and its `file_id` is known:
```bash
cd tofu/proxmox/garage
tofu init
tofu plan -var="proxmox_image_file_id=lvm:vm-9000-disk-0"
tofu apply -var="proxmox_image_file_id=lvm:vm-9000-disk-0"
```

After `tofu apply`, the VM will boot directly into NixOS. Cloud-init will apply the static IP and inject SSH keys. You can then SSH in as `bhamm@10.0.20.21`.

### 3.4 Document the Process
Add a guide to the docs-site so future Proxmox NixOS VMs follow the same pattern:

#### `docker/docs-site/docs/operations/proxmox-images.md`
Outline:
- Why build a custom image (no official NixOS cloud images for Proxmox)
- How to build the generic `proxmox-image` from the flake
- How to upload and restore the `.vma.zst` file
- How to reference the image in OpenTofu
- How cloud-init works with NixOS on Proxmox
- Link to relevant NixOS wiki pages and `nixos-generators` docs

---

## Phase 4: Colmena — NixOS Configuration
**STATUS: PENDING** — Strategy: minimal config first (no Garage, no secrets), verify Colmena works, then layer in Garage.

> **Note:** `disko` is skipped for the initial install because the generic Proxmox image already has a boot disk layout. We will use `fileSystems` mounts for the data drives instead of re-partitioning.

### 4.1 Files to Create

#### `nix/hosts/garage/default.nix`
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
    ./../../profiles/server.nix
  ];

  cfg = {
    networking = {
      static = {
        interface = "ens18"; # Verify after cloud-init / virtio
        address = "10.0.20.21";
        gateway = "10.0.20.1";
        nameservers = [ "10.0.9.2" ];
      };
    };
  };

  # Garage service (to be enabled in a later iteration)
  # services.garage = { ... };

  # Firewall
  # networking.firewall.allowedTCPPorts = [ 3900 3901 3902 ];
}
```

#### `nix/hosts/garage/hardware-configuration.nix`
Minimal template for a Proxmox VM:
```nix
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usbhid" "usb_storage" "sr_mod" "virtio_pci" "virtio_scsi" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" "vfio-pci" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
```

### 4.2 Deploy with Colmena
Once the VM boots from the generic Proxmox image and cloud-init configures the network:
```bash
cd /home/bhamm/repos/bhamm-lab
colmena apply --on garage
```

---

## Phase 5: Post-Deployment Garage Setup

The NixOS module only configures the daemon. Buckets and keys must be created via `garage-manage`.

### 5.1 SSH to Garage VM
```bash
ssh -p 4185 bhamm@10.0.20.21
```

### 5.2 Create Layout, Bucket, and Key
```bash
# 1. Register the single node
sudo garage-manage node id
# Note the node ID output (e.g., e5e4d972-...)

# 2. Assign node to zone
sudo garage-manage zone assign <NODE_ID> japan --capacity 5T

# 3. Create the bucket
sudo garage-manage bucket create ceph-rgw

# 4. Create the access key
sudo garage-manage key create garage-key
# Note the access key ID and secret, or specify them if supported by your Garage version
```

### 5.3 Sync Keys to Secrets
Add the generated `access_key_id` and `secret_access_key` to `secrets.enc.json` under:
```json
"vault_secrets": {
  "core": {
    "garage": {
      "s3_access_key": "...",
      "s3_secret_key": "...",
      "rpc_secret": "...",
      "admin_token": "..."
    }
  }
}
```
Re-encrypt and commit.

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
- [ ] Phase 0: Generate Garage secrets and add to `secrets.enc.json` (deferred)
- [x] Phase 1: Update `ansible/inventory/host_vars/japan.yml` with passthrough vars
- [x] Phase 1: Run Ansible on `japan` and reboot
- [x] Phase 2: Migrate physical SSDs from `method` to `japan`
- [ ] Phase 3: Create `nix/hosts/proxmox-image/` generic NixOS Proxmox image config
- [ ] Phase 3: Build the generic Proxmox image (`nixos-rebuild build-image --image-variant proxmox`)
- [ ] Phase 3: Upload image to Proxmox and restore as a template
- [ ] Phase 3: Update `tofu/proxmox/garage/` OpenTofu code to use the pre-built image
- [ ] Phase 3: Run `tofu apply` to create the VM
- [ ] Phase 3: Document the Proxmox image workflow in `docker/docs-site/docs/operations/proxmox-images.md`
- [ ] Phase 4: Create `nix/hosts/garage/` configuration
- [ ] Phase 4: Deploy with `colmena apply --on garage`
- [ ] Phase 5: Run `garage-manage` commands to create bucket and key
- [ ] Phase 5: Update `secrets.enc.json` with generated Garage S3 credentials
- [ ] Phase 6: Create `kubernetes/manifests/base/garage/` manifests
- [ ] Phase 6: Update ArgoCD `core-green.yaml` to include garage manifests
- [ ] Phase 7: Update `buckets-green.yaml` with R2→Garage restore template
- [ ] Phase 7: Trigger the restore workflow and verify
- [ ] Phase 8: Update `ceph-rgw-backup-green.yaml` to sync rgw → garage → r2/b2
- [ ] Phase 8: Verify backup CronJob runs successfully
- [ ] Phase 8: Destroy TrueNAS VM
