# Indy Proxmox/Ceph Setup & Troubleshooting Log

## Overview

This document summarizes the reconfiguration of the `indy` Proxmox node, including storage migration, Ceph OSD creation, and cluster-wide fallout from an accidental full-cluster Ansible run.

---

## Initial Goals

1. **Move VM storage (`local-vg`)** from `sda3` to dedicated 1TB NVMe (`nvme1n1`)
2. **Keep `sda3`** for root filesystem only
3. **Create 3 Ceph OSDs** on indy:
   - 1TB SSD (`sdd`)
   - 3.5TB SSD (`sdc`)
   - 7TB SSD (`sdb`)
4. **DB/WAL partitions** on 1.4TB NVMe (`nvme0n1`)

---

## Phase 1: Root VG Rename

### Problem
The `local-vg` volume group was originally on `sda3` (boot disk). We needed to free `sda3` for root-only use and move VM storage to `nvme1n1`.

### Solution
Manually renamed `local-vg` → `indy-vg` on `sda3`:

```bash
# On indy node
vgrename local-vg indy-vg
```

Updated all boot-critical configuration files:
- `/etc/fstab` — changed mount source from `local-vg` to `indy-vg`
- `/etc/default/grub` — updated `GRUB_CMDLINE_LINUX` root parameter
- `/boot/grub/grub.cfg` — regenerated with `update-grub`
- Initramfs — rebuilt with `update-initramfs -u -k all`
- Resume config — updated swap resume partition reference

### Result
Reboot successful. Root now on `indy-vg`, `sda3` dedicated to system use.

---

## Phase 2: VM Storage Migration

Created `local-vg` on `nvme1n1` (Sabrent Rocket 4.0 Plus) for VM storage.

Updated `ansible/inventory/host_vars/indy.yml`:
```yaml
storage_vm_device: /dev/nvme1n1
```

Ansible `storage` role created the new `local-vg` on `nvme1n1`.

---

## Phase 3: Ceph OSD Configuration

### Initial Config (indy.yml)

```yaml
ceph_nvme_device: /dev/nvme0n1
ceph_partitions:
  - number: 1
    name: osd1_db
    start: 1GiB
    end: 101GiB      # 100 GiB for 1TB OSD
  - number: 2
    name: osd2_db
    start: 101GiB
    end: 495GiB      # 394 GiB for 3.5TB OSD
  - number: 3
    name: osd3_db
    start: 495GiB
    end: 1300GB      # ~700+ GiB for 7TB OSD

pve_ceph_osds:
  - device: /dev/sdd                  # 1TB
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_PHKS8203003F1P5CGN-part1
    crush.device.class: ssd
  - device: /dev/sdc                  # 3.5TB
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_PHKS8203003F1P5CGN-part2
    crush.device.class: ssd
  - device: /dev/sdb                  # 7TB
    block.db: /dev/disk/by-id/nvme-INTEL_SSDPED1K015TA_PHKS8203003F1P5CGN-part3
    crush.device.class: ssd
```

### Key Decision: Use by-id Paths

Drive letters shift on reboot (especially after kernel updates). We switched to stable `/dev/disk/by-id/` paths for all DB devices to prevent future breakage.

Confirmed by-id on indy:
```
nvme-INTEL_SSDPED1K015TA_PHKS8203003F1P5CGN
```

---

## Troubleshooting: Partition Size Mismatch

### Error
When creating the 7TB OSD, pveceph failed:

```
'/dev/nvme0n1p3' is smaller than requested size '768150112665' bytes
```

### Root Cause
pveceph requires DB partition to be ~10% of OSD capacity. For a 7TB drive, this is ~715 GiB. The original partition was only ~700 GiB.

### Fix
Expanded `nvme0n1p3` from 700 GiB to 779 GiB (leaving ~200GB free on NVMe for future use):

```bash
sudo parted -s /dev/nvme0n1 resizepart 3 1300GB
```

Then re-ran Ansible:
```bash
ansible-playbook -i inventory/hosts debian.yml --limit indy --tags storage,proxmox
```

### Result
All 3 OSDs created successfully on indy:
- `osd.1` — 1TB (`sdd`)
- `osd.2` — 3.5TB (`sdc`)
- `osd.3` — 7TB (`sdb`)

---

## Phase 4: Cluster-Wide Fallout

### The Accident
Despite recommendation to run Ansible with `--limit indy`, a full-cluster run was executed. This caused:

1. **Kernel updates** on all 3 nodes
2. **Reboots** on all 3 nodes
3. **Drive letter shifts** — especially problematic on `japan`

### Japan Drive Letter Fix

Pre-reboot config referenced `sdd`, `sde`, `sdf`. Post-reboot, actual drives were `sda`, `sdb`, `sdc`.

Updated `ansible/inventory/host_vars/japan.yml`:
```yaml
pve_ceph_osds:
  - device: /dev/sda   # was sdd (3.5TB)
  - device: /dev/sdb   # was sde (1TB)
  - device: /dev/sdc   # was sdf (1TB)
```

### Method OSD Removal

The 7TB drive (`sda`) on `method` had errors and was removed from the cluster. The user manually purged `osd.0` from Ceph.

Updated `ansible/inventory/host_vars/method.yml` — removed the 7TB OSD entry entirely.

### Ceph Cluster State

After all changes, cluster had `nobackfill,norebalance` flags set:
- 17.5% objects degraded
- 49% objects misplaced
- 8 OSDs total (after removing method's failing drive and adding indy's 3rd)

These flags were set to prevent massive data movement during the maintenance window. They should be unset once the cluster stabilizes:

```bash
ceph osd unset nobackfill norebalance
```

---

## Phase 5: Talos VM Issues

### Problem
To free up storage for the LVM migration, the ephemeral Talos VMs on indy were manually deleted via Proxmox GUI:
- `green-talos-master-0` (VMID 110)
- `green-talos-worker-0` (VMID 120)

### State Mismatch
Terraform (tofu) state still believed these VMs existed with machine configs applied. When VMs were recreated (either manually or via tofu), they booted into **maintenance mode** because the Talos machine configuration was never actually applied to the new instances.

### Symptoms
- VMs running but unreachable via `talosctl`
- TLS certificate errors: `x509: certificate signed by unknown authority`
- etcd still showed old member `green-talos-master-0` (10.0.30.60)

### Fix

1. **Remove stale etcd member** from healthy master (master-1 at 10.0.30.61):
   ```bash
   talosctl --talosconfig result/talos-config-green.yaml -n 10.0.30.61 etcd remove-member 6adfde2c1331e381
   ```

2. **Force tofu to re-apply machine configs**:
   ```bash
   cd tofu/proxmox/talos
   tofu workspace select green
   tofu apply \
     -replace="talos_machine_configuration_apply.vms[\"green-talos-master-0\"]" \
     -replace="talos_machine_configuration_apply.vms[\"green-talos-worker-0\"]"
   ```

This destroys the stale state entries and pushes fresh Talos configs to the recreated VMs.

---

## Final Indy State

| Device | Role |
|--------|------|
| `sda` (1TB Samsung 870 EVO) | Boot disk — `indy-vg` (root + swap) |
| `sdb` (7TB Micron 5300) | Ceph OSD.3 |
| `sdc` (3.5TB Samsung MZ7L3) | Ceph OSD.2 |
| `sdd` (1TB Samsung 870 EVO) | Ceph OSD.1 |
| `nvme0n1` (1.4TB Intel Optane) | Ceph DB partitions (osd1_db, osd2_db, osd3_db) |
| `nvme1n1` (1TB Sabrent Rocket) | VM storage — `local-vg` |

---

## Lessons Learned

1. **Never run full-cluster Ansible** when doing node-specific storage changes. Always use `--limit <node>`.
2. **Drive letters shift on reboot** — use `/dev/disk/by-id/` paths in all configs.
3. **Ceph DB partitions need ~10% of OSD size** — verify before creating OSDs.
4. **Manually deleting VMs in Proxmox GUI** breaks tofu state. Always use `-replace` or `tofu destroy` to keep state in sync.
5. **Renaming root VG** requires updating fstab, GRUB, initramfs, and resume config — easy to miss one.

---

## Files Modified

- `ansible/inventory/host_vars/indy.yml` — storage + Ceph config
- `ansible/inventory/host_vars/method.yml` — removed failing 7TB OSD
- `ansible/inventory/host_vars/japan.yml` — fixed drive letters
- `plans/indy-proxmox-ceph-setup.md` — this document
