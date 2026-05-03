# Japan Proxmox/Ceph Migration Plan

## Overview

Migrate the `japan` Proxmox node to new storage topology while preserving Ceph mon/mgr identity, Proxmox cluster membership, and garage HBA passthrough configuration.

**Current Topology:**
| Device | Role |
|--------|------|
| nvme0n1 (CT1000P3PSSD8 1TB) | Root (`local-vg`) + VM storage |
| nvme1n1 (WD SN850X 1TB) | Ceph DB/WAL (to be removed) |
| sda (Samsung MZ7L3 3.5TB) | Ceph OSD.18 — OUT |
| sdb (Samsung 870 EVO 1TB) | Ceph OSD.21 — OUT |
| sdc (Samsung 870 EVO 1TB) | Ceph OSD.24 — OUT |

**Target Topology:**
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

## Pre-Flight Findings

### Ceph Status
```
HEALTH_WARN: 1.338% degraded, 9 pgs degraded/undersized
8 OSDs total, 5 in, 3 out (Japan's osd.18, osd.21, osd.24)
Mon quorum: method, japan, indy
Mgr: indy(active), method/japan standbys
```

Japan's OSDs are OUT and empty (0 B used), but still running. Cluster is replicating data to remaining 5 OSDs.

### Storage State
- Root VG is `local-vg` on `nvme0n1p3`
- **Critical:** `/etc/fstab` references `/dev/mapper/japan--vg-root` which does NOT exist. System boots via correct `root=/dev/mapper/local--vg-root` in kernel cmdline. This stale fstab must be fixed during migration.
- VMs on `local-vg`: garage (300), talos-master-2 (112), talos-worker-2 (122)

### Ansible Config Gaps
- `japan.yml` is missing `storage_vm_device` (explains why root VG is `local-vg` not `japan-vg`)
- Ceph by-id paths in `japan.yml` are valid (`nvme-WD_BLACK_SN850X_1000GB_25286M804502`)

---

## Phase 0: Prep & Config Fixes

### 0.1 Install New Hardware
1. Install 240GB SATA SSD
2. Install 1.5TB NVMe in slot freed by nvme1n1 (or new slot)
3. Boot and verify with `lsblk` and `/dev/disk/by-id/`

### 0.2 Backup Critical State
```bash
# On japan
sudo tar czf /tmp/japan-etc-backup.tar.gz /etc/fstab /etc/default/grub /boot/grub/grub.cfg /etc/pve /etc/ceph /etc/modprobe.d/
# Copy off-node
```

### 0.3 Fix `ansible/inventory/host_vars/japan.yml`

**Updated config (already applied):**
```yaml
network_10gb_nics: [enp1s0f0, enp1s0f1]
storage_vm_device: /dev/disk/by-id/nvme-CT1000P3PSSD8_2422492E9226
ceph_nvme_device: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_PHKS8203005G1P5CGN
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
pve_ceph_osds:
  # OSD 1: 3.5TB Samsung MZ7L3 (sdb) → needs largest DB → part3 (384GiB ≈ 11%)
  # NOTE: Ceph requires device in /dev/sdX format, but block.db works with by-id
  - device: /dev/sdb
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_PHKS8203005G1P5CGN-part3
    crush.device.class: ssd
  # OSD 2: 1TB Samsung 870 EVO (sdd) → part1 (100GiB ≈ 10%)
  - device: /dev/sdd
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_PHKS8203005G1P5CGN-part1
    crush.device.class: ssd
  # OSD 3: 1TB Samsung 870 EVO (sdc) → part2 (100GiB ≈ 10%)
  - device: /dev/sdc
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_PHKS8203005G1P5CGN-part2
    crush.device.class: ssd
```

---

## Phase 1: Ceph OSD Rebuild

Do this **before** root migration so the cluster recovers capacity before we take Japan down for cloning.

### 1.1 Stop VMs on Japan
```bash
# On japan
sudo qm stop 300   # garage
sudo qm stop 112   # talos-master-2
sudo qm stop 122   # talos-worker-2
```

### 1.2 Purge Japan OSDs from Ceph Cluster
From a healthy mon (method or indy):
```bash
# Verify these are the correct IDs
ceph osd tree | grep japan
# Should show osd.18, osd.21, osd.24 with weight 0

# Purge them permanently
ceph osd purge osd.18 --yes-i-really-mean-it
ceph osd purge osd.21 --yes-i-really-mean-it
ceph osd purge osd.24 --yes-i-really-mean-it

# Verify
ceph -s
```

### 1.3 Wipe Old OSDs and DB/WAL on Japan
```bash
# On japan
sudo systemctl stop ceph-osd@18 ceph-osd@21 ceph-osd@24

# Deactivate and remove Ceph LVs/VGs
for lv in $(sudo lvs --noheadings -o lv_path | grep 'ceph-' | awk '{print $1}'); do
  sudo lvchange -an "$lv"
done
for dm in $(sudo dmsetup ls --target linear | grep 'ceph-' | awk '{print $1}'); do
  sudo dmsetup remove "$dm"
done
for vg in $(sudo vgs --noheadings -o vg_name | grep 'ceph-' | awk '{print $1}'); do
  sudo vgremove -y "$vg"
done

# Remove PVs from data disks and old DB partitions
sudo pvremove -y /dev/sdb /dev/sdc /dev/sdd
sudo pvremove -y /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part1
sudo pvremove -y /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part2
sudo pvremove -y /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part3

# Wipe signatures
sudo wipefs --all --force /dev/sdb /dev/sdc /dev/sdd
sudo wipefs --all --force /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part1
sudo wipefs --all --force /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part2
sudo wipefs --all --force /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part3
sudo wipefs --all --force /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502
```

> At this point, old nvme1n1 is completely free of Ceph data and can be physically removed **after** the new OSDs are created.

### 1.4 Update japan.yml with New Ceph Config
Update `ceph_nvme_device` to new 1.5TB NVMe by-id and `pve_ceph_osds` with new `block.db` paths. Use `/dev/disk/by-id/` for all devices.

### 1.5 Create New DB/WAL Partitions and OSDs
```bash
# From control node
ansible-playbook -i inventory/hosts debian.yml --limit japan --tags storage,proxmox
```

This will:
- Create partitions on new 1.5TB NVMe (storage role)
- Create new OSDs on sda/sdb/sdc with new DB/WAL (lae.proxmox role)

### 1.6 Verify Cluster Health
```bash
# Watch rebalance
watch -n 5 ceph -s
# Should see Japan's new OSDs join and cluster health improve
```

---

## Phase 2: Root Migration (Live Clone)

### 2.1 Stop All VMs
```bash
sudo qm stop 300
sudo qm stop 112
sudo qm stop 122
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

### 2.6 Verify Boot
```bash
# After reboot
lsblk
vgs  # Should show japan-vg on new SSD, local-vg still on nvme0n1
cat /proc/cmdline  # Should show root=/dev/japan-vg/root
```

---

## Phase 3: VM Storage Reconfiguration

### 3.1 Wipe nvme0n1 and Create local-vg
```bash
# On japan (now booted from 240GB SSD)
sudo wipefs --all --force /dev/nvme0n1
sudo pvcreate /dev/nvme0n1
sudo vgcreate local-vg /dev/nvme0n1
```

### 3.2 Update ansible/inventory/host_vars/japan.yml
Add:
```yaml
storage_vm_device: /dev/disk/by-id/nvme-CT1000P3PSSD8_2422492E9226
```

### 3.3 Run Ansible Storage Role
```bash
ansible-playbook -i inventory/hosts debian.yml --limit japan --tags storage
```

This should:
- Skip root resize (already correct)
- Create `local-vg` on nvme0n1
- Leave `japan-vg` untouched on new SSD

---

## Phase 4: VM Restoration

### 4.1 Restore Garage VM
```bash
cd tofu/proxmox/garage
tofu plan
tofu apply
```

After garage boots:
- Update sops age key for NixOS garage host
- Run `nixos-rebuild switch` or let garage auto-configure via cloud-init + sops
- Verify garage mounts its data disks (HBA passthrough should be intact)

### 4.2 Restore Talos VMs
```bash
cd tofu/proxmox/talos
tofu workspace select green

# Recreate Japan VMs and force machine config re-application
tofu apply \
  -replace="proxmox_virtual_environment_vm.this[\"green-talos-master-2\"]" \
  -replace="proxmox_virtual_environment_vm.this[\"green-talos-worker-2\"]"
```

> The `lifecycle { replace_triggered_by }` on `talos_machine_configuration_apply.vms` should auto-trigger config re-application when the VMs are replaced.

### 4.3 Verify Talos Cluster
```bash
# After VMs are up
talosctl --talosconfig result/talos-config-green.yaml -n 10.0.30.62 health
# Verify all 3 masters and all workers are ready
kubectl get nodes
```

---

## Phase 5: Cleanup

### 5.1 Remove Old nvme1n1
Now that Ceph OSDs are rebuilt with new 1.5TB NVMe, old nvme1n1 is safe to remove:
```bash
# Verify no Ceph signatures remain
lsblk /dev/nvme1n1
wipefs /dev/nvme1n1
# Physically remove drive
```

### 5.2 Update Documentation
- Update `plans/japan-proxmox-ceph-migration.md` with actual by-id paths and any deviations
- Update `ansible/inventory/host_vars/japan.yml` comments to reflect final state

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

## Open Questions / Need Verification

1. **New 1.5TB NVMe by-id path:** Must discover after physical install.
2. **sda by-id path:** Current lsblk shows `ata-SAMSUNG_MZ7L33T8HBLT-00A07_S6ERNT0WB00833` for sda. Confirm this is stable.
3. **240GB SSD device letter:** Will it be `/dev/sda` (shifting existing drives) or `/dev/sdd`? Discover in live environment.
4. **Ceph backfill impact:** With 3 OSDs out and 5 in, cluster is degraded. Bringing 3 new OSDs online will trigger backfill. Ensure network and disk I/O can handle this during migration window.
5. **Garage data restore:** Confirm RGW bucket has all garage data. The garage VM config has `replication_factor = 1` — verify no critical metadata only lives in `/var/lib/garage/meta`.
