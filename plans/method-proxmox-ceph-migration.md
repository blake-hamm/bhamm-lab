# Method Proxmox/Ceph Migration Plan

## Overview

Migrate the `method` Proxmox node to new storage topology: replace consumer NVMe DB/WAL with enterprise 1.5TB Intel NVMe, migrate VM storage (`local-vg`) to the freed consumer NVMe, and repurpose the 1TB SSD as a 3rd Ceph OSD.

**Post-Micron-Removal Topology (actual):**
| Device | Role | by-id |
|--------|------|-------|
| sda (Lexar SSD NS100 128GB) | Root/boot (`method-vg`) | `ata-Lexar_SSD_NS100_128GB_NLD743W1041010S301` |
| sdc (Samsung 870 EVO 1TB) | VM storage (`local-vg`) → **moved to nvme0n1** | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201685W` |
| nvme0n1 (SHGP31-1000GM-2 1TB) | Ceph DB/WAL (old) → **new VM storage** | `nvme-SHGP31-1000GM-2_AS0CN42841190CT25` |
| nvme1n1 (Intel SSDPED1K015TA 1.5TB) | **New Ceph DB/WAL** (3 partitions) | `nvme-INTEL_SSDPE21K015TA_PHKE0350002P1P5CGN` |
| sdb (SAMSUNG MZ7L3 3.5TB) | Ceph OSD | `ata-SAMSUNG_MZ7L33T8HBLT-00AK1_S6ZDNE0T701154` |
| sdd (Samsung 870 EVO 1TB) | Ceph OSD | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201833B` |

> **Note:** Micron 5100 7TB was physically removed before migration. Device letters shifted: `sdb`→`sda`, `sdc`→`sdb`, `sdd`→`sdc`, `sde`→`sdd`.

> **Key Difference from Japan:** Method already has a dedicated boot SSD. No root migration or live clone needed.

---

## Phase 0: Prep & Hardware Issues ✅ DONE

### 0.1 Japan Back Online ✅
Japan was offline initially but came back. Cluster recovered to quorum (`method,indy,japan`) before destructive work began.

### 0.2 U.2 NVMe Detection Fix ✅
Intel U.2 NVMe was not detected by H12SSL-i motherboard. Fixed by setting JCFG1 jumper to pins 1-2 (SMBus enabled) per Supermicro manual. Drive appeared as `nvme1n1` after reboot.

### 0.3 Install Intel NVMe & Verify ✅
```bash
ssh bhamm@10.0.20.11 "lsblk; ls -la /dev/disk/by-id/ | grep INTEL"
```
Recorded by-id: `nvme-INTEL_SSDPE21K015TA_PHKE0350002P1P5CGN`

### 0.4 Update `ansible/inventory/host_vars/method.yml` ✅
- `storage_vm_device`: temporarily pointed to `sdc` (current local-vg location)
- `ceph_nvme_device`: Intel NVMe by-id path
- 3 DB partitions: part1 (100GB), part2 (100GB), part3 (384GB)
- 3 OSDs mapped to post-removal device letters: `sdb` (3.5TB), `sdc` (1TB, commented during Phase 1), `sdd` (1TB)
- New GPU passthrough IDs added: `8086:e223`, `8086:e2f7` (Intel Battlemage G21)

---

## Phase 1: Ceph OSD Rebuild ✅ DONE

### 1.1 Purge Old OSDs ✅
`osd.20` and `osd.22` were already absent from CRUSH map (previously purged). Confirmed no active OSDs on method.

### 1.2 Clean Up Old Ceph LVMs ✅
Removed old Ceph VGs from `sdb`, `sdd`, and `nvme0n1p1/p2`:
```bash
sudo lvremove -y ...
sudo vgremove -y ...
```

### 1.3 Wipe Drives ✅
```bash
sudo wipefs -af /dev/sdb
sudo wipefs -af /dev/sdd
sudo wipefs -af /dev/nvme0n1
```

### 1.4 Run Ansible (First Pass — 2 OSDs) ✅
`sdc` OSD entry was temporarily commented out because `local-vg` still lived on `sdc`.

```bash
ansible-playbook -i inventory/hosts debian.yml --tags storage,proxmox
```
> Run on all 3 nodes, not `--limit method`. The `lae.proxmox` role requires facts from all cluster members.

Created 2 new OSDs: `sdd` (1TB, Intel part1) and `sdb` (3.5TB, Intel part3).

### 1.5 Fix Indy Host Vars (by-id swap) ✅
`indy.yml` had `nvme0n1`/`nvme1n1` swapped. After reboot, device numbers shifted and the config pointed `storage_vm_device` at the Intel DB drive. Fixed to use stable by-id paths.

---

## Phase 2: VM Storage Migration (local-vg → nvme0n1) ✅ DONE

### 2.1 Stop VMs ✅
```bash
sudo qm stop 111   # green-talos-master-1
sudo qm stop 121   # green-talos-worker-1
sudo qm stop 123   # green-talos-worker-intel-gpu
sudo qm stop 124   # green-talos-worker-amd-gpu
```

### 2.2 pvmove sdc → nvme0n1 ✅
```bash
sudo pvcreate /dev/nvme0n1
sudo vgextend local-vg /dev/nvme0n1
sudo pvmove /dev/sdc /dev/nvme0n1   # ~270GB, took significant time (SATA→NVMe)
sudo vgreduce local-vg /dev/sdc
sudo pvremove /dev/sdc
```

### 2.3 Wipe sdc ✅
```bash
sudo wipefs -af /dev/sdc
```

---

## Phase 3: Create 3rd OSD on sdc ✅ DONE

### 3.1 Update `method.yml` ✅
- `storage_vm_device` → `/dev/disk/by-id/nvme-SHGP31-1000GM-2_AS0CN42841190CT25`
- Uncommented `sdc` OSD entry with `block.db: ...-part2`

### 3.2 Run Ansible (Second Pass — 3rd OSD) ✅
```bash
ansible-playbook -i inventory/hosts debian.yml --tags storage,proxmox
```
Created 3rd OSD on `sdc` (1TB, Intel part2).

---

## Phase 4: Start VMs & Verify

### 4.1 Start VMs
```bash
sudo qm start 111
sudo qm start 121
sudo qm start 123
sudo qm start 124
```

### 4.2 Verify Talos Cluster
```bash
talosctl --talosconfig result/talos-config-green.yaml -n 10.0.30.61 health
kubectl get nodes
```

### 4.3 Final Verification Checklist
```bash
# Ceph
sudo ceph -s
sudo ceph osd tree
sudo ceph osd df

# Storage
sudo lsblk
sudo pvs
sudo vgs
sudo lvs

# VMs
sudo qm list

# Network
ping 10.0.30.61  # talos-master-1
ping 10.0.30.71  # talos-worker-1
ping 10.0.30.73  # talos-worker-intel-gpu
ping 10.0.30.74  # talos-worker-amd-gpu
```

---

## Open Questions / Future Work

1. **Unused 7TB Micron:** Physically removed. Can be repurposed for another node or backups.
2. **Indy by-id:** All NVMe paths now use by-id. Verify no other hosts have raw `/dev/nvmeXnX` in configs.
