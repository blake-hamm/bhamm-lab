# Method Proxmox/Ceph Migration Plan

## Overview

Migrate the `method` Proxmox node to new storage topology: replace consumer NVMe DB/WAL with enterprise 1.5TB Intel NVMe, migrate VM storage (`local-vg`) to the freed consumer NVMe, and repurpose the 1TB SSD as a 3rd Ceph OSD.

**Current Topology:**
| Device | Role | by-id |
|--------|------|-------|
| sdb (Lexar SSD NS100 128GB) | Root/boot (`method-vg`) | `ata-Lexar_SSD_NS100_128GB_NLD743W1041010S301` |
| sdd (Samsung 870 EVO 1TB) | VM storage (`local-vg`) | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201685W` |
| nvme0n1 (SHGP31-1000GM-2 1TB) | Ceph DB/WAL (osd.20, osd.22) | `nvme-SHGP31-1000GM-2_AS0CN42841190CT25` |
| sdc (SAMSUNG MZ7L3 3.5TB) | Ceph OSD.22 | `ata-SAMSUNG_MZ7L33T8HBLT-00AK1_S6ZDNE0T701154` |
| sde (Samsung 870 EVO 1TB) | Ceph OSD.20 | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201833B` |
| sda (Micron 5100 7TB) | Unused (previously failed OSD) | `ata-Micron_5100_MTFDDAK7T6TBY_172517D04D6E` |

**Target Topology (post-migration):**
| Device | Role | by-id |
|--------|------|-------|
| sdb (Lexar 128GB) | Root/boot (`method-vg`) | `ata-Lexar_SSD_NS100_128GB_NLD743W1041010S301` |
| nvme0n1 (SHGP31-1000GM-2 1TB) | VM storage (`local-vg`) | `nvme-SHGP31-1000GM-2_AS0CN42841190CT25` |
| nvme1n1 (Intel SSDPED1K015TA 1.5TB) | Ceph DB/WAL (3 partitions) | `nvme-INTEL_SSDPED1K015TA_????` (TBD after install) |
| sdc (SAMSUNG MZ7L3 3.5TB) | Ceph OSD.22 | `ata-SAMSUNG_MZ7L33T8HBLT-00AK1_S6ZDNE0T701154` |
| sde (Samsung 870 EVO 1TB) | Ceph OSD.20 | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201833B` |
| sdd (Samsung 870 EVO 1TB) | Ceph OSD.X (new) | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201685W` |
| sda (Micron 5100 7TB) | Unused / future use | `ata-Micron_5100_MTFDDAK7T6TBY_172517D04D6E` |

> **Key Difference from Japan:** Method already has a dedicated boot SSD (`sdb`). No root migration or live clone needed.

---

## ⚠️ Critical Blocker: Japan is Offline

**Current Ceph Status (from method):**
```
health: HEALTH_WARN
  1/3 mons down, quorum method,indy
  3 osds down
  1 host (3 osds) down
  834186/2502558 objects degraded (33.333%)
```

Japan's mon and all 3 OSDs are down. **Do NOT proceed with method migration until:**
1. Japan is powered on and reachable at `10.0.20.13`
2. Ceph reports `HEALTH_OK` with all 8 OSDs up
3. `ceph osd tree` shows all `japan` OSDs as `up`

If method's 2 OSDs are taken out while japan is down, only indy's 3 OSDs remain active. With `size=3 min_size=2` pools, some PGs may become unreadable or the cluster may freeze I/O.

---

## Phase 0: Prerequisites ✅

### 0.1 Verify Japan is Online and Healthy
```bash
ssh bhamm@10.0.20.13 "sudo ceph -s"
# Expected: HEALTH_OK, 8/8 OSDs up, quorum method,indy,japan
```

### 0.2 Install New Hardware
Install 1.5TB Intel NVMe (SSDPED1K015TA) in method.

Verify it appears and record by-id:
```bash
ssh bhamm@10.0.20.11 "lsblk; ls -la /dev/disk/by-id/ | grep INTEL"
```
> **Note:** NVMe device number may shift after reboot. Use by-id in all configs.

### 0.3 Backup Critical State
```bash
# On method
sudo tar czf /tmp/method-etc-backup-$(date +%Y%m%d).tar.gz /etc/fstab /etc/default/grub /boot/grub/grub.cfg /etc/pve /etc/ceph /etc/modprobe.d/
scp /tmp/method-etc-backup-*.tar.gz bhamm@10.0.20.11:/backups/
```

---

## Phase 1: Ceph OSD Rebuild with New DB/WAL

**Approach:** Destructive but fast. Mark method OSDs out, purge immediately, wipe, and recreate on new Intel NVMe DB/WAL. The user tolerates temporary instability.

### 1.1 Mark Method OSDs as Out
From any healthy mon (method or indy):
```bash
sudo ceph osd out osd.20 osd.22
```

### 1.2 (Optional) Set Recovery Flags
If backfill causes too much load during the maintenance window:
```bash
sudo ceph osd set nobackfill norebalance
# Unset later: sudo ceph osd unset nobackfill norebalance
```

### 1.3 Stop and Purge OSDs
```bash
# On method
sudo systemctl stop ceph-osd@20 ceph-osd@22

# From healthy mon
sudo ceph osd purge osd.20 --yes-i-really-mean-it
sudo ceph osd purge osd.22 --yes-i-really-mean-it
```

### 1.4 Clean Up Old Ceph LVMs and Wipe Disks
```bash
# On method
# Verify old ceph VGs are gone
sudo vgs | grep ceph
sudo lvs | grep osd

# Wipe old DB partitions on consumer NVMe (nvme0n1)
sudo wipefs --all --force /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/nvme0n1p3
sudo wipefs --all --force /dev/nvme0n1

# Wipe OSD data disks (sdc, sde)
sudo wipefs --all --force /dev/sdc
sudo wipefs --all --force /dev/sde
```

### 1.5 Create DB Partitions on New Intel NVMe
```bash
# On method
sudo parted -s /dev/nvme1n1 mklabel gpt
sudo parted -s /dev/nvme1n1 mkpart osd1_db 1GiB 101GiB    # 100 GiB for 1TB OSD
sudo parted -s /dev/nvme1n1 mkpart osd2_db 101GiB 201GiB  # 100 GiB for 1TB OSD
sudo parted -s /dev/nvme1n1 mkpart osd3_db 201GiB 585GiB  # 384 GiB for 3.5TB OSD
```

### 1.6 Update Ansible Config
Edit `ansible/inventory/host_vars/method.yml`:

```yaml
# NEW: VM storage moves to freed consumer NVMe
storage_vm_device: /dev/disk/by-id/nvme-SHGP31-1000GM-2_AS0CN42841190CT25

# NEW: Ceph DB/WAL on enterprise Intel NVMe
ceph_nvme_device: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_<SERIAL>
ceph_partitions:
  - number: 1
    name: osd1_db
    start: 1GiB
    end: 101GiB
  - number: 2
    name: osd2_db
    start: 101GiB
    end: 201GiB
  - number: 3
    name: osd3_db
    start: 201GiB
    end: 585GiB

# NEW: 3 OSDs — sdd becomes the new 3rd OSD
pve_ceph_osds:
  - device: /dev/sde
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_<SERIAL>-part1
    crush.device.class: ssd
  - device: /dev/sdd
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_<SERIAL>-part2
    crush.device.class: ssd
  - device: /dev/sdc
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_<SERIAL>-part3
    crush.device.class: ssd
```

> **Drive Letter Warning:** `sdc`, `sdd`, `sde` may shift on reboot. Verify actual device letters match by-id mapping before running Ansible. Use by-id for `block.db`, but Ceph `device:` field requires `/dev/sdX` format.

### 1.7 Run Ansible to Create New OSDs
```bash
ansible-playbook -i inventory/hosts debian.yml --limit method --tags storage,proxmox
```
> Run with `--limit method` because `lae.proxmox` Ceph tasks are node-local. If the role complains about missing cluster facts, run cluster-wide.

### 1.8 Verify Cluster Health
```bash
sudo ceph -s
sudo ceph osd tree
```
Expected: `HEALTH_OK` or `HEALTH_WARN` with active backfill. Method should have 2 new OSDs up (sdc, sde).

---

## Phase 2: VM Storage Migration (local-vg → nvme0n1)

After Ceph is healthy with new DB/WAL, migrate VM storage from `sdd` to the freed `nvme0n1`.

**Data on sdd:** ~270GB VM disks + small cloudinit volumes.

### 2.1 Stop All VMs on Method
```bash
# On method
sudo qm stop 111   # green-talos-master-1
sudo qm stop 121   # green-talos-worker-1
sudo qm stop 123   # green-talos-worker-intel-gpu
sudo qm stop 124   # green-talos-worker-amd-gpu
```

### 2.2 Add nvme0n1 to local-vg and pvmove
```bash
# On method
# Create PV on wiped nvme0n1
sudo pvcreate /dev/nvme0n1

# Extend local-vg
sudo vgextend local-vg /dev/nvme0n1

# Migrate all extents from sdd to nvme0n1
sudo pvmove /dev/sdd /dev/nvme0n1

# Remove sdd from local-vg
sudo vgreduce local-vg /dev/sdd
sudo pvremove /dev/sdd
```

### 2.3 Verify Migration
```bash
sudo vgs
sudo lvs
sudo pvs
# local-vg should show only /dev/nvme0n1 as PV
# All VM LVs should be on nvme0n1
```

### 2.4 Start VMs
```bash
sudo qm start 111
sudo qm start 121
sudo qm start 123
sudo qm start 124
```

### 2.5 Verify VMs
```bash
sudo qm list
# Talos health check from workstation:
talosctl --talosconfig result/talos-config-green.yaml -n 10.0.30.61 health
kubectl get nodes
```

---

## Phase 3: Create 3rd OSD on sdd

Now that `sdd` is fully freed from `local-vg`, create the 3rd Ceph OSD.

### 3.1 Wipe sdd
```bash
sudo wipefs --all --force /dev/sdd
```

### 3.2 Run Ansible Again
The `method.yml` already has the 3rd OSD entry for `sdd` (added in Phase 1.6). Re-run:
```bash
ansible-playbook -i inventory/hosts debian.yml --limit method --tags storage,proxmox
```

### 3.3 Verify
```bash
sudo ceph -s
sudo ceph osd tree
```
Expected: `HEALTH_OK`, 9 OSDs total (indy 3 + japan 3 + method 3).

---

## Phase 4: Cleanup & Verification

### 4.1 Remove Old Consumer NVMe Partitions (if any remnant)
```bash
# On method
lsblk
# Should show nvme0n1 as single device with local-vg, no partitions
```

### 4.2 Update Proxmox Storage Config (if needed)
```bash
sudo pvesm status
sudo cat /etc/pve/storage.cfg
```
Ensure `lvm` storage still points to `local-vg`. It should — VG name didn't change, only underlying PV moved.

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

## Rollback Plan

### If Ceph OSD Creation Fails
1. `proxmox_reset_ceph=true` with old config to wipe and start over
2. Verify by-id paths and device letters
3. Re-run ansible

### If pvmove Fails or is Interrupted
1. `pvmove --abort` to cancel
2. Check LVs: `lvs -a -o+devices`
3. Re-run `pvmove` or use `lvconvert --repair` if needed
4. sdd remains in local-vg; postpone OSD creation until resolved

### If VMs Fail to Start After Migration
1. Verify `local-vg` LVs are present and on `nvme0n1`
2. Check Proxmox storage config: `cat /etc/pve/storage.cfg`
3. Verify disk paths in VM configs: `cat /etc/pve/qemu-server/111.conf`
4. Restart `pvedaemon` and `pveproxy` if needed

---

## Open Questions / Need Verification

1. **Japan status:** Is it intentionally powered off? Turn it on before proceeding.
2. **Intel NVMe serial:** Record `nvme-INTEL_SSDPED1K015TA_` by-id after physical install.
3. **Drive letter stability:** Will `sdc/sdd/sde` shift after installing the new NVMe? Verify with `lsblk` and `ls -la /dev/disk/by-id/` after install but before running Ansible.
4. **pvmove duration:** ~270GB of VM disks. Estimate 30-60 min downtime for VMs on method.
5. **Unused 7TB Micron (sda):** Consider adding as a 4th OSD later, or repurpose for local backups.
