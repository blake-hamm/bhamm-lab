# Japan Proxmox/Ceph Migration Plan

## Overview

Migrate the `japan` Proxmox node to new storage topology while preserving Ceph mon/mgr identity, Proxmox cluster membership, and garage HBA passthrough configuration.

**Final Topology (post-migration):**
| Device | Role | by-id |
|--------|------|-------|
| sda (KINGSTON SA400S37 240GB) | Root/boot (`japan-vg`) | `ata-KINGSTON_SA400S37240G_50026B77845B74E3` |
| nvme1n1 (WD_BLACK SN850X 1TB) | VM storage (`local-vg`) | `nvme-WD_BLACK_SN850X_1000GB_25286M804502` |
| nvme2n1 (Intel SSDPED1K015TA 1.5TB) | Ceph DB/WAL | `nvme-INTEL_SSDPED1K015TA_PHKS8203005G1P5CGN` |
| sdb (SAMSUNG MZ7L3 3.5TB) | Ceph OSD.3 | `ata-SAMSUNG_MZ7L33T8HBLT-00A07_S6ERNT0WB00833` |
| sdc (Samsung 870 EVO 1TB) | Ceph OSD.5 | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201871R` |
| sdd (Samsung 870 EVO 1TB) | Ceph OSD.4 | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201842M` |
| ~~nvme0n1 (CT1000P3PSSD8 1TB)~~ | ~~Removed (wiped for laptop)~~ | ~~`nvme-CT1000P3PSSD8_2422492E9226`~~ |
| ~~nvme1n1 (WD SN850X 1TB)~~ | ~~Removed~~ | ~~`nvme-WD_BLACK_SN850X_1000GB_25286M804502`~~ |

> **Note:** NVMe device numbers shifted between live ISO boot and normal boot. Intel NVMe is `nvme2n1` in normal boot, WD_BLACK is `nvme1n1`. Ceph `block.db` uses by-id paths so this shift is harmless.

**Original Pre-Migration Topology:**
| Device | Role | by-id |
|--------|------|-------|
| sda (KINGSTON SA400S37 240GB) | Root/boot (`japan-vg`) | `ata-KINGSTON_SA400S37240G_50026B77845B74E3` |
| nvme0n1 (CT1000P3PSSD8 1TB) | VM storage (`local-vg`) | `nvme-CT1000P3PSSD8_2422492E9226` |
| nvme1n1 (Intel SSDPED1K015TA 1.5TB) | Ceph DB/WAL | `nvme-INTEL_SSDPED1K015TA_PHKS8203005G1P5CGN` |
| sdb (SAMSUNG MZ7L3 3.5TB) | Ceph OSD (3.5TB) | `ata-SAMSUNG_MZ7L33T8HBLT-00A07_S6ERNT0WB00833` |
| sdc (Samsung 870 EVO 1TB) | Ceph OSD (1TB) | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201871R` |
| sdd (Samsung 870 EVO 1TB) | Ceph OSD (1TB) | `ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201842M` |

**Key Decision: Live Clone Root**
- Preserves Ceph mon/mgr state, Proxmox cluster auth, SSH host keys, SSL certs, `/etc/pve`
- Avoids fresh-install bootstrap issues experienced previously
- Root LV is only 100GB, easily cloned to 240GB SSD

---

## Final Status

### Ceph Status
```
HEALTH_OK
8 OSDs total, 8 in, 0 out
Mon quorum: method, japan, indy
Mgr: indy(active), method/japan standbys
```

Japan's old OSDs (osd.18, osd.21, osd.24) were purged and replaced with new OSDs on new Intel NVMe DB/WAL. Cluster backfilled successfully.

### Storage State
- Root VG is `japan-vg` on `sda3` (KINGSTON 240GB) — migration complete
- VM storage VG is `local-vg` on `nvme1n1` (WD_BLACK SN850X 1TB) — migrated from CT1000
- VMs auto-started after root migration because configs were rsynced with root filesystem
- Old `local-vg/root` and `local-vg/swap_1` copies removed — reclaimed ~104GB
- WD_BLACK (nvme1n1) wiped clean — ready for physical removal
- VMs on `local-vg`: garage (300), talos-master-2 (112), talos-worker-2 (122) — all running

---

## Phase 0: Prep & Config Fixes ✅ DONE

### 0.1 Install New Hardware ✅
240GB SATA SSD and 1.5TB Intel NVMe installed. Device letters shifted:
- `sda` = new 240GB KINGSTON SSD
- `sdb` = 3.5TB SAMSUNG MZ7L3 (was `sda`)
- `sdc` = 1TB Samsung 870 EVO (was `sdb`)
- `sdd` = 1TB Samsung 870 EVO (was `sdc`)
- `nvme1n1` = new 1.5TB Intel NVMe
- `nvme2n1` = old WD SN850X 1TB

### 0.2 Backup Critical State
**Skip for now.** Will do right before root migration (Phase 2.1).

### 0.3 Fix `ansible/inventory/host_vars/japan.yml` ✅

**Config applied and verified.** Key points:
- `ceph_nvme_device` points to new Intel NVMe by-id
- OSD `device` fields use `/dev/sdX` format (Ceph requirement)
- OSD `block.db` fields use by-id paths (works correctly)
- `storage_vm_device` added but was **temporarily commented out** during Phase 1 because `japan-vg` does not yet exist — the storage role computes `storage_root_vg` from this variable and would crash trying to resize a non-existent VG.

---

## Phase 1: Ceph OSD Rebuild ✅ DONE

Old OSDs (osd.18, osd.21, osd.24) were already OUT. Purged from cluster, disks wiped, new OSDs created on new Intel NVMe DB/WAL. Cluster backfilled to HEALTH_OK.

> **VMs were NOT stopped.** Ceph OSD rebuild is independent of VM storage (`local-vg` on nvme0n1).

> **Critical:** `storage_vm_device` was temporarily commented out in `japan.yml` before running Ansible because the storage role computes `storage_root_vg = japan-vg` when this variable is set, but `japan-vg` doesn't exist until Phase 2 root migration. With it set, the role crashes trying to resize a non-existent VG.

### 1.1-1.3 OSD destruction and wipe ✅
- OSDs purged from healthy mon
- Ceph LVs/VGs already cleaned up (verified via SSH — no ceph-* VGs or LVs remain)
- Data disks (`sdb`, `sdc`, `sdd`) and old DB partitions (`nvme2n1p1-3`) wiped

### 1.4-1.5 Ansible run ✅
```bash
# storage_vm_device was temporarily commented out in japan.yml first
ansible-playbook -i inventory/hosts debian.yml --tags storage,proxmox
```
> Run on all 3 nodes, not `--limit japan`. The `lae.proxmox` role requires facts from all cluster members.

### 1.6 Cluster health ✅
Backfilled from HEALTH_WARN to HEALTH_OK. Japan now has 3 new OSDs (osd.3, osd.4, osd.5) with new Intel NVMe DB/WAL.

---

## Phase 2: Root Migration (Live Clone) ✅ DONE

> **Do NOT mark method OSDs as out yet.** Wait until Japan root migration is complete and Ceph is HEALTH_OK with Japan back online. Marking method out while Japan is down for cloning would leave only indy's 3 OSDs active — too few for host-level failure domain.

### 2.1 Stop All VMs
```bash
sudo qm stop 300   # garage
sudo qm stop 112   # talos-master-2
sudo qm stop 122   # talos-worker-2
```

### 2.1a Backup Critical State (do this now, before reboot)
```bash
# On japan
sudo tar czf /tmp/japan-etc-backup-$(date +%Y%m%d).tar.gz /etc/fstab /etc/default/grub /boot/grub/grub.cfg /etc/pve /etc/ceph /etc/modprobe.d/
# Copy off-node
scp /tmp/japan-etc-backup-*.tar.gz bhamm@10.0.20.11:/backups/
```

### 2.2 Boot Debian Live USB
- Attach Debian live USB to japan
- Reboot and select USB boot
- Verify new 240GB SSD appears as `/dev/sda` (`ata-KINGSTON_SA400S37240G_50026B77845B74E3`)

### 2.3 Clone Root Filesystem
```bash
# In live environment, become root
sudo -i

# Identify devices
lsblk
# Old root device: /dev/nvme0n1 (has local-vg)
# New root device: /dev/sda (240GB SSD)

# Partition new SSD to match old layout
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart ESP fat32 1MiB 977MiB
parted -s /dev/sda mkpart boot ext4 977MiB 1954MiB
parted -s /dev/sda mkpart lvm 1954MiB 100%
parted -s /dev/sda set 1 esp on

# Format EFI and boot
mkfs.vfat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

# Create PV, VG on new SSD
pvcreate /dev/sda3
vgcreate japan-vg /dev/sda3

# Create LVs to match old sizes
lvcreate -L 100G -n root japan-vg
lvcreate -L 4G -n swap_1 japan-vg

# Copy root filesystem
mkfs.ext4 /dev/japan-vg/root
mkdir -p /mnt/oldroot /mnt/newroot
mount /dev/local-vg/root /mnt/oldroot
mount /dev/japan-vg/root /mnt/newroot

# Use rsync for live copy (preserves hardlinks, sparse files)
rsync -aHx --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/boot --exclude=/boot/efi /mnt/oldroot/ /mnt/newroot/

# Copy boot partitions
mkdir -p /mnt/oldboot /mnt/newboot
mount /dev/nvme0n1p2 /mnt/oldboot
mount /dev/sda2 /mnt/newboot
rsync -aH /mnt/oldboot/ /mnt/newboot/

mkdir -p /mnt/oldefi /mnt/newefi
mount /dev/nvme0n1p1 /mnt/oldefi
mount /dev/sda1 /mnt/newefi
rsync -aH /mnt/oldefi/ /mnt/newefi/

# Copy swap (or just mkswap)
mkswap /dev/japan-vg/swap_1
```

### 2.4 Update Boot Configuration on New Drive
```bash
# Mount pseudo-filesystems for chroot
mount --bind /dev /mnt/newroot/dev
mount --bind /proc /mnt/newroot/proc
mount --bind /sys /mnt/newroot/sys
mount --bind /run /mnt/newroot/run

# Chroot
chroot /mnt/newroot

# Update fstab
cat > /etc/fstab << 'EOF'
/dev/mapper/japan--vg-root /               ext4    errors=remount-ro 0       1
UUID=NEW-BOOT-UUID /boot           ext4    defaults        0       2
UUID=NEW-EFI-UUID  /boot/efi       vfat    umask=0077      0       1
/dev/japan-vg/swap_1 none            swap    sw              0       0
EOF

# Get actual UUIDs
blkid /dev/sda2 >> /etc/fstab  # boot
blkid /dev/sda1 >> /etc/fstab  # efi
# Edit fstab to use correct UUIDs

# Update GRUB
echo 'GRUB_CMDLINE_LINUX="root=/dev/japan-vg/root iommu=pt vfio-pci.ids=1000:0097 quiet"' > /etc/default/grub.d/10-root-lv.cfg
update-grub

# Install GRUB on new drive
grub-install /dev/sda

# Update initramfs
update-initramfs -u -k all

# Fix resume config (if any)
# Check /etc/initramfs-tools/conf.d/resume and update if needed

exit
```

### 2.5 Reboot from New SSD
```bash
# Exit chroot, unmount, reboot
umount -R /mnt/newroot
umount /mnt/newboot /mnt/newefi /mnt/oldboot /mnt/oldefi /mnt/oldroot
reboot
```

> **Critical:** Ensure BIOS boot order prioritizes new 240GB SSD (`sda`).

### 2.6 Verify Boot ✅
Booted successfully from KINGSTON SSD. Verified:
- `cat /proc/cmdline` shows `root=/dev/japan-vg/root`
- `japan-vg` on `sda3` with `root` (100G) and `swap_1` (4G)
- `local-vg` still on `nvme0n1p3` with all VM disks intact
- VMs auto-started from configs copied by rsync

> **Issue encountered:** Kingston ESP `grub.cfg` still pointed to old nvme0n1p2 UUID after `grub-install` in chroot. The ESP stub `grub.cfg` was not updated by `grub-install`. Fixed by manually updating `/mnt/sda1/EFI/debian/grub.cfg` to search for Kingston `/boot` partition UUID (`08985d2a-4585-4f90-9ac5-e9e0ea74c434`) instead of old nvme0n1p2 UUID.

---

## Phase 3: VM Storage Reconfiguration ✅ DONE

VM storage migrated from `nvme0n1p3` (CT1000) to `nvme1n1` (WD_BLACK) via `pvmove` after root migration completed. The rsync excluded `/boot` and VM disks, so all VM data stayed intact.

### 3.1 Cleanup old root/swap copies from local-vg
Old `local-vg/root` and `local-vg/swap_1` LVs (rsynced copies, not mounted) were removed:
```bash
sudo lvremove -y local-vg/root local-vg/swap_1
```
CT1000 was fully wiped and is ready for reuse in laptop.

### 3.2 Re-enable `storage_vm_device` in `japan.yml`
`storage_vm_device` was uncommented in `ansible/inventory/host_vars/japan.yml`:
```yaml
storage_vm_device: /dev/disk/by-id/nvme-CT1000P3PSSD8_2422492E9226
```

### 3.3 Run Ansible Storage Role (optional)
```bash
ansible-playbook -i inventory/hosts debian.yml --limit japan --tags storage
```

This will:
- Skip root resize (already correct)
- Ensure `local-vg` on nvme0n1 is properly configured
- Leave `japan-vg` untouched on new SSD

---

## Phase 4: VM Restoration ✅ NOT NEEDED

VMs auto-started after root migration because their Proxmox configs (in `/etc/pve/qemu-server/`) were copied by rsync along with the root filesystem. VM 112 had `onboot: 1`, and all three VMs came up automatically.

### 4.1 Garage VM
Already running. HBA passthrough configuration intact.

### 4.2 Talos VMs
Already running. No recreation needed.

### 4.3 Verify Talos Cluster
```bash
# After VMs are up
talosctl --talosconfig result/talos-config-green.yaml -n 10.0.30.62 health
# Verify all 3 masters and all workers are ready
kubectl get nodes
```

---

## Phase 5: Cleanup ✅ DONE

### 5.1 Remove Old WD_BLACK (nvme1n1)
Drive was fully wiped and is ready for physical removal:
```bash
sudo wipefs --all --force /dev/nvme1n1p1 /dev/nvme1n1p2 /dev/nvme1n1p3
sudo wipefs --all --force /dev/nvme1n1
```

> **Note:** In normal boot, WD_BLACK is `nvme1n1` and Intel is `nvme2n1` (opposite of live ISO boot). Ceph uses by-id paths so this is harmless.

**Action:** Physically remove WD_BLACK SN850X 1TB from Japan.

### 5.2 Update Documentation ✅
- `plans/japan-proxmox-ceph-migration.md` updated with final topology and completion status
- `ansible/inventory/host_vars/japan.yml` updated — `storage_vm_device` re-enabled

### 5.3 Verify Final State
```bash
# Ceph
ceph -s  # Should be HEALTH_OK

# Storage
lsblk
pvs
vgs
lvs

# VMs
qm list

# Network
ping 10.0.20.21  # garage
ping 10.0.30.62  # talos-master-2
```

---

## Rollback Plan

If root clone fails to boot:
1. Reboot and select `nvme0n1` in BIOS boot menu
2. System boots from old root (`local-vg`) unchanged
3. Debug clone issues (fstab, GRUB, initramfs)
4. Re-attempt clone

If Ceph OSD creation fails:
1. `proxmox_reset_ceph=true` with old config to wipe and start over
2. Verify by-id paths
3. Re-run ansible

---

## Future Work: Method Node Migration

After Japan is fully migrated and stable:
1. Mark method's OSDs as `out` from a healthy node
2. Wait for backfill to complete (cluster stays at 6 active OSDs: indy 3 + japan 3)
3. Purge, wipe, and rebuild method's OSDs with new hardware/config
4. Method root migration (if needed)

## Open Questions / Need Verification

1. ✅ ~~New 1.5TB NVMe by-id path~~ — `nvme-INTEL_SSDPED1K015TA_PHKS8203005G1P5CGN`
2. ✅ ~~sda by-id path~~ — Device letters shifted; sda is 240GB SSD, sdb is 3.5TB Samsung
3. ✅ ~~240GB SSD device letter~~ — `/dev/sda` (shifted existing drives)
4. ✅ ~~Ceph backfill impact~~ — Completed successfully, HEALTH_OK
5. **Garage data restore:** Confirm RGW bucket has all garage data. The garage VM config has `replication_factor = 1` — verify no critical metadata only lives in `/var/lib/garage/meta`.
