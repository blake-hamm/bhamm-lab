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

## Phase 3: Build Generic NixOS Raw Image + Provision VM
**STATUS: REVISED** — After multiple failed attempts with the `.vma.zst` template/clone approach (disk interface mismatches, cross-node storage migration errors, EFI configuration issues), we are switching to a **raw image direct-download approach**. This is cleaner for a single VM and avoids Proxmox template/clone complexities.

### Lessons Learned (Template/Clone Approach)
1. NixOS `proxmox-image.nix` builds images with `virtio0` disk interface and `ide2` cloud-init — overriding these in Terraform causes boot failures.
2. Proxmox cannot clone from shared storage (`osd`) to local storage (`lvm`) across nodes.
3. The `clone` block + explicit `disk` block causes disk interface conflicts.
4. EFI disks must be configured on the template before cloning; otherwise `bios = "ovmf"` fails.

### Why Raw Image is Better for This Use Case
- **No template lifecycle:** Download image directly to Proxmox, create VM in one step
- **No clone semantics:** Avoid disk interface mismatches and storage migration issues
- **Declarative:** Image source is a URL/file in Terraform config
- **Simpler for single VM:** Template benefits (fast cloning) are irrelevant when provisioning one VM

### Architecture
```
┌─────────────────┐     ┌──────────────────────────┐     ┌──────────────────┐
│  NixOS Build    │────▶│  Raw Image               │────▶│  Proxmox `local` │
│  (make-disk-image)│    │  (NFS/HTTP/Local)        │     │  (staging store) │
└─────────────────┘     └──────────────────────────┘     └──────────────────┘
                                                                  │
                                                                  ▼
                                              ┌───────────────────────────┐
                                              │  OpenTofu creates VM on   │
                                              │  `lvm` with file_id ref   │
                                              │  + cloud-init drive       │
                                              └───────────────────────────┘
```

### Critical Fixes from Code Review

The following corrections were identified during review and are incorporated below:

1. **GRUB device = `nodev`** (not `/dev/vda`): For pure EFI boot, GRUB should not install to the MBR.
2. **`networking.useNetworkd = true`**: Required so cloud-init's network configuration is actually applied by systemd-networkd.
3. **Initrd modules include `virtio_scsi` + `sd_mod`**: The OpenTofu config uses `interface = "scsi0"`, so the initrd must load the SCSI drivers. `virtio_blk` is removed since we use SCSI, not virtio-blk.
4. **`flake.nix` uses a separate module file**: The `make-disk-image.nix` call must receive `config`, `pkgs`, `lib`, and `modulesPath` via proper module arguments, not from the flake's `let` block.
5. **Serial device for debugging**: Added to the OpenTofu config to match `console=ttyS0` kernel parameter, enabling boot log viewing via Proxmox console.

### 3.0 Refactor NixOS Profiles for Reusability
**STATUS: COMPLETE**

Already done in previous iterations:
- ✅ `nix/modules/core/base.nix` — universal core modules
- ✅ `nix/profiles/base.nix` — imports base module
- ✅ `nix/profiles/server.nix` — refactored to import base + full modules
- ✅ `nix/hosts/iso/default.nix` — fixed to use `base.nix`

### 3.1 Build the Generic NixOS Raw Image

Create a NixOS configuration that builds a raw image (instead of `.vma.zst`). The image must include:
- **UEFI boot** (`partitionTableType = "efi"`)
- **Cloud-init** for Proxmox metadata (IP, SSH keys, hostname)
- **QEMU guest agent** for Proxmox integration
- **SSHD** for remote access
- **Grow partition** to resize disk on first boot
- **GRUB** bootloader (EFI-compatible)

#### `nix/hosts/proxmox-image/default.nix`
```nix
{ config, lib, pkgs, modulesPath, shared, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ../../profiles/base.nix
  ];

  # Boot: GRUB with EFI support (nodev for pure EFI, no MBR)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  # Ensure systemd-networkd is active so cloud-init network config is applied
  networking.useNetworkd = true;

  # Cloud-init for Proxmox metadata (IP, SSH keys, hostname)
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # QEMU guest agent for Proxmox integrations
  services.qemuGuest.enable = true;

  # SSH on port 22 for initial provisioning (cloud-init, emergency access)
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings.PermitRootLogin = lib.mkDefault "prohibit-password";
  };

  # Inject our authorized keys into the bhamm user
  users.users.${shared.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn6e5VeOkY4WcW0wPmz8uWj+yd+kulj7Ls7upTdKFUO gitea@bhamm-lab.com"
  ];

  # Allow sudo without password for wheel during initial bootstrap
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  # Filesystems: ext4 with auto-resize
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  boot.growPartition = true;
  boot.kernelParams = [ "console=ttyS0" ];
  # virtio_scsi + sd_mod required for scsi0 disk interface in Proxmox
  boot.initrd.availableKernelModules = [ "uas" "virtio_pci" "virtio_scsi" "sd_mod" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  system.stateVersion = shared.nixVersion;
}
```

#### `flake.nix` addition

Add a new module file that defines the raw image build, then reference it in `nixosConfigurations`:

**`nix/hosts/proxmox-image/img-build.nix`:**
```nix
{ config, pkgs, lib, modulesPath, ... }:
{
  system.build.image = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;
    format = "raw";
    partitionTableType = "efi";
    diskSize = "auto";
    additionalSpace = "512M";
    bootSize = "256M";
  };
}
```

**`flake.nix`:**
```nix
proxmox-image = nixpkgs.lib.nixosSystem {
  system = shared.system;
  modules = [
    (import ./nix/hosts/proxmox-image)
    ./nix/hosts/proxmox-image/img-build.nix
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
nix build .#nixosConfigurations.proxmox-image.config.system.build.image
```

The build produces a file like `nixos.img` in the result directory.

#### Stage the image for Proxmox

The image must be placed on the Proxmox node's `local` datastore (which maps to `/var/lib/vz/template/iso/` for `iso` content type). Proxmox's `iso` content type indexes `.img` files natively.

```bash
scp ./result/nixos.img root@10.0.20.15:/var/lib/vz/template/iso/
```

**Note:** Do not use `.qcow2` extension — Proxmox's `iso` content type only indexes `.iso` and `.img` files. The NixOS build produces `nixos.img` natively when `format = "raw"`.

### 3.2 OpenTofu VM Configuration (Raw Image Direct Download)

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

# Reference the already-copied NixOS image on Proxmox storage
data "proxmox_virtual_environment_file" "nixos_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.node_name
  file_name    = "nixos.img"
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
    model   = "virtio"
    bridge  = var.net_bridge
    trunks  = var.net_trunks
    vlan_id = var.net_vlan_id
    mtu     = var.net_mtu
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id = var.datastore_boot
    type         = "4m"
  }

  # Main OS disk: raw image placed on lvm
  disk {
    datastore_id = var.datastore_boot
    file_id      = data.proxmox_virtual_environment_file.nixos_image.id
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    size         = var.boot_size
    file_format  = "raw"
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

  # Serial device for boot debugging (matches console=ttyS0 kernel param)
  serial_device {
    device = "socket"
  }

  # Cloud-Init on ide2 (standard Proxmox cloud-init location)
  initialization {
    datastore_id = var.datastore_boot
    interface    = "ide2"
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

variable "datastore_boot" {
  description = "Datastore for the VM boot disk"
  default     = "lvm"
  type        = string
}

variable "vm_id" {
  default = 300
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

variable "net_vlan_id" {
  default = 20
  type    = number
}

variable "net_mtu" {
  default = 9000
  type    = number
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
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com"
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

**Prerequisite:** The image must already be on the Proxmox node at `/var/lib/vz/template/iso/nixos.img`.

```bash
cd tofu/proxmox/garage
tofu init
tofu plan
tofu apply
```

After `tofu apply`, the VM will boot directly into NixOS. Cloud-init will apply the static IP and inject SSH keys. You can then SSH in as `bhamm@10.0.20.21`.

### 3.4 Verify the VM

```bash
# Check VM status on Proxmox
ssh root@10.0.20.15 "qm status 300"

# SSH into the VM
ssh -p 4185 bhamm@10.0.20.21

# Verify cloud-init worked
cat /var/log/cloud-init.log | grep -i "success"

# Verify qemu-guest-agent
systemctl status qemu-guest-agent

# Verify network
ip addr show
ip route show
```

### 3.5 Document the Process

Add a guide to the docs-site so future Proxmox NixOS VMs follow the same pattern:

#### `docker/docs-site/docs/operations/proxmox-images.md`
Outline:
- Why build a custom image (no official NixOS cloud images for Proxmox)
- Two approaches: `.vma.zst` templates vs raw image direct download
- How to build the raw image from the flake
- How to copy the image to Proxmox storage
- How to reference the image in OpenTofu via data source
- How cloud-init works with NixOS on Proxmox
- Lessons learned and gotchas (disk interfaces, cloud-init device, EFI)
- Link to relevant NixOS wiki pages

---

## Phase 4: Colmena — NixOS Configuration
**STATUS: PENDING** — Strategy: minimal config first (no Garage, no secrets), verify Colmena works, then layer in Garage.

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
      backend = "networkd";
      static = {
        interface = "ens18";     # Verify with `ip link` after first boot
        address = "10.0.20.21";
        prefixLength = 24;       # Explicit; matches 10.0.20.0/24
        gateway = "10.0.20.1";
        nameservers = [ "10.0.9.2" ];
      };
    };
  };

  # Hand off network control from cloud-init to NixOS networkd
  services.cloud-init.network.enable = lib.mkForce false;

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

Once the VM boots from the raw image and cloud-init configures the network:
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
- [x] Phase 3: Refactor NixOS profiles (`base.nix`, `server.nix`)
- [x] Phase 3: Fix `nix/hosts/iso/default.nix` to import `base.nix`
- [x] Phase 3: Create `nix/hosts/proxmox-image/` generic NixOS image config
- [ ] Phase 3: **REVISED** — Update `nix/hosts/proxmox-image/default.nix` for raw image (GRUB nodev, networkd, scsi modules)
- [ ] Phase 3: **REVISED** — Create `nix/hosts/proxmox-image/img-build.nix` for make-disk-image invocation
- [ ] Phase 3: **REVISED** — Update `flake.nix` with `proxmox-image` build target
- [ ] Phase 3: Build the raw image
- [ ] Phase 3: Stage/host the raw image for Proxmox download
- [ ] Phase 3: **REVISED** — Rewrite `tofu/proxmox/garage/main.tf` for raw image download + disk file_id approach
- [ ] Phase 3: **REVISED** — Update `tofu/proxmox/garage/variables.tf` with new variables
- [ ] Phase 3: Run `tofu apply` to create the VM
- [ ] Phase 3: Verify VM boots, cloud-init applies network, SSH works
- [ ] Phase 3: Document the Proxmox image workflow
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

---

## Appendix: Phase 3 Detailed Steps (Raw Image Approach)

### A.1 Clean Up Previous Attempts

```bash
# Destroy any partially-created VM 300 on japan
ssh root@10.0.20.15 "qm destroy 300 --purge 2>/dev/null || true"

# Remove old templates
ssh root@10.0.20.11 "qm destroy 9000 --purge 2>/dev/null || true"
ssh root@10.0.20.15 "qm destroy 9000 --purge 2>/dev/null || true"
```

### A.2 Update NixOS Image Config for raw image

Edit `nix/hosts/proxmox-image/default.nix`:
- Change `boot.loader.grub.device` to `"nodev"` (pure EFI, no MBR)
- Add `networking.useNetworkd = true`
- Replace `virtio_blk` with `virtio_scsi` + `sd_mod` in initrd modules
- Keep cloud-init, qemu-guest-agent, sshd, growPartition as-is

### A.3 Add raw image build target to `flake.nix`

Create `nix/hosts/proxmox-image/img-build.nix` with the `make-disk-image.nix` invocation using proper module arguments. Then add the `proxmox-image` entry to `nixosConfigurations` in `flake.nix`.

### A.4 Build the Image

```bash
nix build .#nixosConfigurations.proxmox-image.config.system.build.image
```

### A.5 Stage the Image

Copy the image to the Proxmox node:
```bash
scp ./result/nixos.img root@10.0.20.15:/var/lib/vz/template/iso/
```

### A.6 Update OpenTofu Config

Replace `tofu/proxmox/garage/main.tf` and `variables.tf` with the data source approach (see Section 3.2 above).

### A.7 Apply

```bash
cd tofu/proxmox/garage
tofu init
tofu apply
```

### A.8 Verify

```bash
ssh -p 4185 bhamm@10.0.20.21
# Check cloud-init log, network, qemu-guest-agent
```
