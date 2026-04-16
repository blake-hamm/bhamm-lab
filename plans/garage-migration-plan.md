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

Before any code is written, the following hardware details must be discovered **on the `method` node** (where the disks and HBA currently reside).

### 0.1 Discover HBA PCIe ID
Run on `method` to identify the HBA controller:
```bash
lspci -nn | grep -i "sata\|sas\|hba\|lsi\|broadcom"
```
Expected output format: `0000:c1:00.0 SATA controller [1b21:1064]`
The **vendor:device ID** (e.g., `1b21:1064`) is what Ansible needs.

### 0.2 Discover Disk `/dev/disk/by-id/` Paths
Run on `method`:
```bash
ls -l /dev/disk/by-id/ | grep -E "ata-|nvme-|scsi-|usb-"
```
Document the exact stable paths for the three SSDs (2x 2TB, 1x 1TB).

### 0.3 Secrets to Generate
The following secrets must be created and added to `secrets.enc.json` (under `vault_secrets.core.garage`):
- `GARAGE_ACCESS_KEY_ID`
- `GARAGE_SECRET_ACCESS_KEY`
- `GARAGE_ADMIN_TOKEN`
- `GARAGE_RPC_SECRET` (32-byte hex, e.g. `openssl rand -hex 32`)

---

## Phase 1: Ansible — Enable PCIe Passthrough on Japan

The `japan` node has never used PCIe passthrough. It must be enabled via the `lae.proxmox` role **before** the VM is created.

### 1.1 Modify `ansible/inventory/host_vars/japan.yml`
Add the passthrough variables (discovered in Phase 0.1):
```yaml
pve_pcie_passthrough_enabled: true
pve_iommu_passthrough_mode: true
pve_iommu_unsafe_interrupts: false
pve_pcie_ovmf_enabled: false
pve_pci_device_ids:
  - id: "<VENDOR:DEVICE>"  # e.g., "1b21:1064"
pve_vfio_blacklist_drivers:
  - name: "<host_driver>"  # e.g., "ahci" or "mpt3sas"
```

### 1.2 Run Ansible
```bash
ansible-playbook -i ansible/inventory/hosts ansible/debian.yml --limit japan
```

### 1.3 Reboot Japan
The role configures GRUB and modprobe, but **does not auto-reboot** for passthrough changes. Reboot manually:
```bash
ssh root@10.0.20.15 -p 4185 reboot
```
Verify after reboot:
```bash
dmesg | grep -i vfio
cat /sys/kernel/iommu_groups/*/devices
```

---

## Phase 2: Physical Migration

1. **Power off the TrueNAS VM** (VM ID 199 on `method`).
2. **Physically remove** the three SSDs from the `method` backplane.
3. **Install** the three SSDs into the backplane of `japan`.
4. **Verify disk visibility** on `japan`:
   ```bash
   ls -l /dev/disk/by-id/
   ```

---

## Phase 3: OpenTofu — Provision the NixOS VM

Create `tofu/proxmox/garage/` with the following files.

### 3.1 Files to Create

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

resource "proxmox_virtual_environment_download_file" "nixos" {
  content_type   = "iso"
  datastore_id   = var.datastore_iso
  node_name      = var.node_name
  url            = var.nixos_url
  file_name      = var.nixos_file
  upload_timeout = 2400
}

resource "proxmox_virtual_environment_vm" "garage" {
  name          = "garage"
  node_name     = var.node_name
  vm_id         = var.vm_id
  tags          = ["tofu", "garage", "nixos"]
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

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

  boot_order = ["scsi0", "ide3"]

  operating_system {
    type = "l26"
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.nixos.id
    interface = "ide3"
  }

  disk {
    datastore_id = var.datastore_boot
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    file_format  = "raw"
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
      keys = var.ssh_keys
    }
  }
}
```

#### `tofu/proxmox/garage/variables.tf`
```hcl
variable "proxmox_url" {
  default = "https://10.0.20.15:8006"
  type    = string
}

variable "datastore_iso" {
  default = "cephfs"
  type    = string
}

variable "node_name" {
  default = "japan"
  type    = string
}

variable "nixos_url" {
  description = "NixOS minimal ISO URL"
  default     = "https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-x86_64-linux.iso"
  type        = string
}

variable "nixos_file" {
  default = "nixos-minimal-25.11.iso"
  type    = string
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
  description = "PCIe IDs for the HBA controller"
  type        = list(string)
  default     = [] # Populate after Phase 0 discovery
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
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.73.0"
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

### 3.2 NixOS Installation Strategy
The OpenTofu module above provisions the VM using the **NixOS minimal ISO** with Cloud-Init for network/SSH injection. After the VM boots:

1. SSH into the live ISO:
   ```bash
   ssh -p 4185 bhamm@10.0.20.21
   ```
2. Run `nixos-anywhere` or a disko+install script to install the host configuration from `nix/hosts/garage`.

**Recommended approach:** Use the existing `nixos-anywhere` flake input. Create a one-time install script:
   ```bash
   nix run github:nix-community/nixos-anywhere -- --flake .#garage --target-host bhamm@10.0.20.21
   ```

### 3.3 Apply OpenTofu
```bash
cd tofu/proxmox/garage
tofu init
tofu plan
tofu apply
```

---

## Phase 4: Colmena — NixOS Configuration

### 4.1 Files to Create

#### `nix/hosts/garage/default.nix`
```nix
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
        interface = "ens18"; # Verify after cloud-init / virtio
        address = "10.0.20.21";
        gateway = "10.0.20.1";
        nameservers = [ "10.0.9.2" ];
      };
    };
  };

  # Garage service
  services.garage = {
    enable = true;
    package = pkgs.garage;
    settings = {
      metadata_dir = "/var/lib/garage/meta";
      data_dir = [
        { path = "/mnt/disk1/garage"; capacity = "2T"; }
        { path = "/mnt/disk2/garage"; capacity = "2T"; }
        { path = "/mnt/disk3/garage"; capacity = "1T"; }
      ];
      replication_factor = 1;
      consistency_mode = "consistent";
      rpc_secret = config.sops.secrets."garage/rpc_secret".path;
      rpc_bind_addr = "[::]:3901";
      s3_api = {
        api_bind_addr = "[::]:3900";
        s3_region = "garage";
        root_domain = ".s3.garage";
      };
      s3_web = {
        bind_addr = "[::]:3902";
        root_domain = ".web.garage";
      };
      admin = {
        api_bind_addr = "127.0.0.1:3903";
        admin_token = config.sops.secrets."garage/admin_token".path;
      };
    };
  };

  # Disk mounts (paths must match Phase 0.2 discovery)
  fileSystems."/mnt/disk1" = {
    device = "/dev/disk/by-id/<DISK_1_BY_ID>";
    fsType = "ext4";
    autoFormat = true; # Requires disko or initial mkfs
  };
  fileSystems."/mnt/disk2" = {
    device = "/dev/disk/by-id/<DISK_2_BY_ID>";
    fsType = "ext4";
    autoFormat = true;
  };
  fileSystems."/mnt/disk3" = {
    device = "/dev/disk/by-id/<DISK_3_BY_ID>";
    fsType = "ext4";
    autoFormat = true;
  };

  # Ensure mount directories exist
  systemd.tmpfiles.rules = [
    "d /mnt/disk1 0755 root root -"
    "d /mnt/disk2 0755 root root -"
    "d /mnt/disk3 0755 root root -"
    "d /var/lib/garage/meta 0755 garage garage -"
  ];

  # sops-nix for secrets
  sops.secrets."garage/rpc_secret" = {
    sopsFile = ../../secrets.enc.json;
    format = "json";
    key = "vault_secrets.core.garage.rpc_secret";
    owner = "garage";
    group = "garage";
  };
  sops.secrets."garage/admin_token" = {
    sopsFile = ../../secrets.enc.json;
    format = "json";
    key = "vault_secrets.core.garage.admin_token";
    owner = "garage";
    group = "garage";
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 3900 3901 3902 ];
}
```

#### `nix/hosts/garage/hardware-configuration.nix`
Generate this with `nixos-generate-config --show-hardware-config` after installation, or start with a minimal template:
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

#### `nix/hosts/garage/disko.nix`
Use `disko` to declaratively partition the boot drive:
```nix
{ inputs, ... }: {
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      boot = {
        device = "/dev/disk/by-id/<BOOT_DISK_BY_ID>"; # The virtual boot disk
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "1G";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
```

### 4.2 Deploy with Colmena
After `nixos-anywhere` installs the base system:
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

- [ ] Phase 0: Discover HBA ID and disk `/dev/disk/by-id/` paths
- [ ] Phase 0: Generate Garage secrets and add to `secrets.enc.json`
- [ ] Phase 1: Update `ansible/inventory/host_vars/japan.yml` with passthrough vars
- [ ] Phase 1: Run Ansible on `japan` and reboot
- [ ] Phase 2: Migrate physical SSDs from `method` to `japan`
- [ ] Phase 3: Create `tofu/proxmox/garage/` OpenTofu code
- [ ] Phase 3: Run `tofu apply` to create the VM
- [ ] Phase 3: Install NixOS via `nixos-anywhere` or disko script
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
