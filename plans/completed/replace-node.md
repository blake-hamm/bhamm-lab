# Replace 'stale' Node with 'japan' Node

## Executive Summary

This plan replaces the dead 'stale' node (10.0.20.13) with a new 'japan' node (10.0.20.15) in the Proxmox/Ceph cluster.

**Critical Strategy:** Japan is added *first* to restore monitor quorum and add capacity *before* formally removing stale. This minimizes risk during the degraded state.

**Current State:** Ceph HEALTH_OK, 3 monitors up (method, indy, japan), japan has 3 OSDs contributing capacity
**Target State:** Ceph HEALTH_OK, 3 monitors up, stale fully removed from cluster

**Automation Strategy:** All of Phase 1 (Proxmox install, cluster join, Ceph deployment) is handled by Ansible using the `lae.proxmox` role. Phase 2 (removal) is manual since `lae.proxmox` only supports creation, not destruction.

**Implementation Changes from Original Plan:**
- ✅ Switched from LVM-based Ceph DB to GPT partitions (100GiB, 100GiB, 384GiB) — more compatible with pveceph
- ✅ Added `dns-search bhamm-lab.com` to all network templates to fix FQDN resolution
- ✅ Fixed security role cross-host variable loops for `--limit` support

---

## Hardware Architecture

### Transplant to japan

| Device | Source | Purpose |
|--------|--------|---------|
| 1TB NVMe | NEW | Proxmox boot drive |
| 1TB NVMe | stale (salvaged) | Ceph DB/WAL device (GPT partitions) |
| 1TB EVO SSD | stale (salvaged) | OSD.6 (with partitioned DB) |
| 1TB EVO SSD | Extra inventory | OSD.7 (with partitioned DB) |
| 3.84TB SSD | stale (salvaged) | OSD.8 (with partitioned DB) |

### Network Configuration (japan)

| Interface | Usage | IP Address | VLAN |
|-----------|-------|------------|------|
| enp1s0f0 | Trunk (metal + k8s) | 10.0.20.15/24, 10.0.30.15/24 | 20, 30 |
| enp1s0f1 | Ceph private | 10.0.50.15/24 | 50 |

### Ceph OSD Mapping (Post-Deployment)

| OSD | Device | DB Location | Size | Source |
|-----|--------|-------------|------|--------|
| osd.6 | /dev/disk/by-id/ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201871R | /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part1 | 100g DB | 1TB EVO (stale) |
| osd.7 | /dev/disk/by-id/ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201842M | /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part2 | 100g DB | 1TB EVO (extra) |
| osd.8 | /dev/disk/by-id/ata-SAMSUNG_MZ7L33T8HBLT-00A07_S6ERNT0WB00833 | /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part3 | 384g DB | 3.84TB (stale) |

**Note:** DB partition sizes are >=10% of OSD capacity (pveceph requirement). 1TB OSDs use 100GiB DB, 3.84TB OSD uses 384GiB DB. WAL is colocated within the DB partition (modern BlueStore behavior).

---

## Phase 1: Add japan to Cluster (Pre-Removal)

**STATUS: ✅ COMPLETED**

### Step 1.1: Pre-flight Verification ✅

**CRITICAL:** Before making any changes, verify the current cluster state and Ansible safety:

```bash
# Verify cluster health (expect degraded but functional)
ceph -s
ceph mon stat

# Verify proxmox_reset_ceph is false
grep proxmox_reset_ceph ansible/inventory/group_vars/proxmox.yml
# MUST be: proxmox_reset_ceph: false
# If true, the lae.proxmox role will WIPE ALL OSD DEVICES on the target host.
```

**WARNING:** The `proxmox_reset_ceph` variable in `group_vars/proxmox.yml` must remain `false`. If set to `true` for any reason, the `ansible/roles/proxmox/tasks/ceph.yml` task will run `wipefs --all` on every device listed in `pve_ceph_osds` — destroying all data on those disks.

### Step 1.2: Configure Ansible Inventory

**Create:** `ansible/inventory/host_vars/japan.yml`

```yaml
network_10gb_nics: [enp1s0f0, enp1s0f1]
ceph_nvme_device: /dev/nvme1n1
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
  - device: /dev/sdb
    block.db: /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part1
    crush.device.class: ssd
  - device: /dev/sdc
    block.db: /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part2
    crush.device.class: ssd
  - device: /dev/sda
    block.db: /dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502-part3
    crush.device.class: ssd
```

**Key Design Decisions:**
- **GPT partitions, not LVM:** pveceph's `osd create` command cannot use LVM logical volumes as `--db_dev` (resolves to `/dev/dm-X` which Proxmox can't identify in its disk inventory)
- **DB-only partitions:** Modern BlueStore colocates WAL within the DB device when only `block.db` is specified. No separate WAL partition needed.
- **Persistent device naming:** Use `/dev/disk/by-id/` paths instead of `/dev/sdX` to handle device name shifts between reboots

**Create:** `ansible/templates/network/japan.j2`

```j2
# The loopback network interface
auto lo
iface lo inet loopback

# Physical NIC (10Gb) on trunk port: no IP assigned here
auto enp1s0f0
iface enp1s0f0 inet manual
    mtu 9000

# VLAN-aware Bridge on enp1s0f0
auto vmbr0
iface vmbr0 inet manual
    bridge-ports enp1s0f0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vlan-filtering yes
    bridge-vids 1 20 30
    mtu 9000

# Metal interface on VLAN 20 via the bridge:
auto vmbr0.20
iface vmbr0.20 inet static
    address 10.0.20.15/24
    netmask 255.255.255.0
    gateway 10.0.20.2
    dns-nameservers 10.0.9.2
    dns-search bhamm-lab.com
    mtu 9000

# Kubernetes interface on VLAN 30 via the bridge:
auto vmbr0.30
iface vmbr0.30 inet static
    address 10.0.30.15/24
    netmask 255.255.255.0
    dns-nameservers 10.0.9.2
    dns-search bhamm-lab.com
    mtu 9000

# Ceph Interface (10Gb) - VLAN 50 on enp1s0f1:
auto enp1s0f1
iface enp1s0f1 inet manual
    mtu 9000

auto enp1s0f1.50
iface enp1s0f1.50 inet static
    address 10.0.50.15/24
    netmask 255.255.255.0
    vlan-raw-device enp1s0f1
    mtu 9000
```

**Modify:** `ansible/inventory/hosts`

```ini
# Add to inventory
japan ansible_host=10.0.20.15

[debian]
method
indy
japan  # Add japan
stale   # Keep stale for now

[proxmox]
method
indy
japan  # Add japan
stale   # Keep stale for now
```

### Step 1.3: Update Storage Role for LVM Support (Backward Compatible) ✅

**Status:** Created `proxmox-lvm.yml` for LVM support, but **reverted to using GPT partitions** after discovering pveceph cannot use LVM logical volumes as `--db_dev`.

**Files created:**
- `ansible/roles/storage/tasks/proxmox-lvm.yml` — LVM implementation (documented but not used)
- Updated `ansible/roles/storage/tasks/main.yml` — reverted back to single `proxmox.yml` include

### Step 1.4: Dry Run ✅

Before deploying, run ansible in check mode to verify all tasks are correct:

```bash
cd /home/bhamm/repos/bhamm-lab/ansible
ansible-playbook main.yml --limit japan --check --diff
```

Review the output carefully:
- Network tasks should configure enp1s0f0/enp1s0f1 with VLANs
- Storage tasks should create `vg_ceph_db` with 3 logical volumes
- Proxmox tasks should install PVE, join cluster, create monitor, create OSDs
- `proxmox_reset_ceph` tasks should be SKIPPED (verify this!)
- Post tasks should run Ceph configuration (prometheus, msgr2, etc.)

**Note:** Some tasks will report "changed" in check mode but won't actually execute (e.g., cluster join, Ceph operations). Check mode validates syntax and variable resolution but cannot fully simulate state-changing operations like `pvecm add`.

### Step 1.5: Deploy japan via Ansible ✅

**Deployment completed successfully.** Japan is reachable via SSH using password auth for the initial connection:

```bash
cd /home/bhamm/repos/bhamm-lab/ansible
ansible-playbook main.yml --limit japan --ask-pass --ask-become-pass
```

This single playbook run executes the following roles in order:

| Role | What it does on japan |
|------|----------------------|
| security | Harden SSH, configure keys |
| network | Apply `japan.j2` network template (VLANs 20, 30, 50) |
| storage | Create LVM volume group + logical volumes for Ceph DB |
| proxmox → pre.yml | Install Docker, configure NTP |
| proxmox → ceph.yml | SKIPPED (`proxmox_reset_ceph: false`) |
| proxmox → lae.proxmox | Install PVE, join cluster, create mon.japan, create 3 OSDs |
| proxmox → post.yml | Enable Ceph prometheus, msgr2, configure ceph.conf, create cephfs subvolumegroup |

**What the `lae.proxmox` role handles automatically:**
- Installs Proxmox VE packages
- Joins japan to the existing cluster via `pvecm add` (throttled to 1 node at a time)
- Creates `mon.japan` (japan is not the first monitor node, so it runs the "additional monitors" task)
- Creates 3 OSDs via `pveceph osd create` with `--db_dev` for each
- Creates Ceph manager on japan
- Configures SSH, APT repositories, kernel modules

**Important:** The `pve_reboot_on_kernel_update: true` setting in group_vars may cause japan to reboot during the playbook if a kernel update is applied. This is fine — japan is a fresh node with no running workloads.

### Step 1.6: Post-Deployment Verification ✅

**Verified:** Ceph is HEALTH_OK with all OSDs active. Japan successfully joined the cluster with 3 OSDs.

After the playbook completed, verified from method or indy:

```bash
# Verify japan joined the cluster
pvecm status
# Shows: method, indy, japan (3 nodes)

# Verify monitor quorum restored
ceph mon stat
# Shows: method, indy, japan (3 monitors)

# Verify OSDs are up
ceph osd tree
# Shows osd.6, osd.7, osd.8 as "up" and "in" on japan

# Check cluster health
ceph -s
# Shows: HEALTH_OK
```

### Step 1.7: Wait for Ceph Recovery ✅

**Status:** Ceph reached HEALTH_OK immediately after deployment. No backfilling required since stale's OSDs were already down.

```bash
watch -n 5 ceph -s
```

**Actual result:**
- Ceph shows **HEALTH_OK** immediately
- All 9 OSDs up (6 on method/indy, 3 on japan)
- No degraded data

**Ready for Phase 2** — stale can now be safely removed.

---

## Post-Deployment Troubleshooting (Completed)

### Issue: Question Mark Icon in Proxmox GUI

**Problem:** Japan showed a gray question mark (?) instead of green checkmark in Proxmox GUI node list.

**Root Cause:** Japan's FQDN was incorrectly resolving as `japan.japan.bhamm-lab.com` due to:
1. Debian installer set hostname as FQDN (`japan.bhamm-lab.com` in `/etc/hosts`)
2. Missing `dns-search` in network templates caused Ansible to generate wrong hosts entries

**Resolution:**

1. **Add `dns-search` to all network templates:**
   - Updated `japan.j2`, `method.j2`, `indy.j2`, `stale.j2`
   - Added `dns-search bhamm-lab.com` to VLAN 20 (management) interfaces

2. **Manual fix on japan:**
   ```bash
   # Fix hostname
   sudo hostnamectl set-hostname japan

   # Fix /etc/resolv.conf
   sudo sed -i 's/search japan.bhamm-lab.com/search bhamm-lab.com/' /etc/resolv.conf

   # Fix /etc/hosts
   sudo sed -i 's/japan.japan.bhamm-lab.com/japan.bhamm-lab.com/' /etc/hosts

   # Restart PVE services
   sudo systemctl restart pve-cluster pvestatd pvedaemon pveproxy
   ```

3. **Re-run full playbook:**
   ```bash
   ansible-playbook ansible/debian.yml
   ```
   This re-generated the cluster hosts block on all nodes with correct FQDN (`japan.bhamm-lab.com`).

### Issue: LVM for Ceph DB Not Compatible with pveceph

**Problem:** Initial plan used LVM logical volumes for Ceph DB (`vg_ceph_db/osdN_db`), but `pveceph osd create --db_dev` cannot use LVM LVs.

**Root Cause:** Proxmox's disk inventory identifies devices by `/dev/sdX` paths, but LVM resolves to `/dev/dm-X` which Proxmox cannot map back to physical devices.

**Resolution:** Switched to GPT partitions with `/dev/disk/by-id/` paths. See updated host_vars/japan.yml and Hardware Architecture section.

### Issue: Security Role Cross-Host Variable Failures

**Problem:** Running `ansible-playbook --limit japan` failed due to security role referencing `hostvars[item].ansible_default_ipv4.address` for all cluster hosts.

**Resolution:** Added `is defined` guards to three cross-host variable loops in `ansible/roles/security/tasks/proxmox.yml`:
- Line 83: `hostvars[item].ansible_default_ipv4.address is defined`
- Line 84: `hostvars[item].ansible_hostname is defined`
- Line 85: `hostvars[item].ansible_fqdn is defined`

However, full playbook must still run against all proxmox hosts because `lae.proxmox` role requires all host facts.

---

## Phase 2: Remove stale from Cluster

### Step 2.1: Pre-Removal Verification

From **method** or **indy**, verify:

```bash
# Confirm healthy cluster
ceph -s
# Should show HEALTH_OK

# Verify monitor quorum — check which monitors exist
ceph mon stat
# Take note of all monitors. mon.indy MUST exist before removing mon.stale.

# Verify japan OSDs are healthy
ceph osd tree
# Should show osd.6, osd.7, osd.8 as "up" and "in" on japan

# Check for replication jobs referencing stale
cat /etc/pve/replication.cfg | grep stale
# Should be empty — remove any entries if present
```

**IMPORTANT:** If `mon.indy` does NOT appear in `ceph mon stat`, you must create it BEFORE removing `mon.stale`:

```bash
# SSH into indy
pveceph mon create
```

If `mon.indy` already exists (which it should — it was created when the cluster was originally set up), you can skip this step.

### Step 2.2: Remove Ceph OSDs from stale

**OSD IDs to remove:** osd.2, osd.5 (these are the down OSDs on stale)

```bash
# SSH into method or indy

# Mark OSDs as out
ceph osd out osd.2
ceph osd out osd.5

# Wait for backfill to complete — this redistributes stale's data
watch ceph -s

# Remove from CRUSH map
ceph osd crush remove osd.2
ceph osd crush remove osd.5

# Remove authentication keys
ceph auth del osd.2
ceph auth del osd.5

# Remove OSDs from cluster
ceph osd rm osd.2
ceph osd rm osd.5
```

### Step 2.3: Remove Ceph Monitor from stale

```bash
# SSH into method or indy
pveceph mon destroy
# Select mon.stale when prompted
```

**Verify after removal:**

```bash
ceph mon stat
# Should show monitors without mon.stale (e.g., method, indy, japan)
```

### Step 2.4: Remove stale from Proxmox Cluster

```bash
# SSH into method or indy
pvecm delnode stale
```

**Verify:**

```bash
pvecm status
# Should show only: method, indy, japan
```

### Step 2.5: Clean Up Ansible Inventory

**Remove stale from:** `ansible/inventory/hosts`

```ini
[debian]
method
indy
japan
# stale REMOVED

[proxmox]
method
indy
japan
# stale REMOVED
```

**Delete:**
- `ansible/inventory/host_vars/stale.yml`
- `ansible/templates/network/stale.j2`

---

## Phase 3: Update Infrastructure Configuration

### Step 3.1: Update OpenTofu Talos Configuration

**File:** `tofu/proxmox/talos/variables.tf`

Change:
```hcl
{ name = "stale", multiplier = 1 }
```

To:
```hcl
{ name = "japan", multiplier = 1 }
```

**File:** `tofu/proxmox/talos/main.tf`

Replace:
```hcl
node {
  name    = "stale"
  address = "10.0.20.13"
  port    = "4185"
}
```

With:
```hcl
node {
  name    = "japan"
  address = "10.0.20.15"
  port    = "4185"
}
```

### Step 3.2: Update Kubernetes Manifests (Future)

The following files reference stale's IP (10.0.20.13) and will need updating when the cluster is stable. These are managed by ArgoCD and should be updated after Ceph is healthy:

- `kubernetes/manifests/base/ceph/csi-rbd-all.yaml` — monitor IP
- `kubernetes/manifests/base/ceph/csi-cephfs-all.yaml` — monitor IPs
- `kubernetes/manifests/core/dashy/config-all.yaml` — dashboard URL
- `kubernetes/manifests/base/monitor/kube-prom-stack-all.yaml` — Prometheus targets

---

## Rollback Plan

### Scenario: Japan fails to join cluster

1. **Stop** — Do not remove stale from inventory
2. Investigate japan network connectivity (VLANs 20, 30, 50)
3. Verify japan can reach method/indy on all VLANs
4. Check Proxmox cluster logs: `journalctl -u pve-cluster`
5. Check Ansible verbose output for `pvecm add` errors
6. Retry from Step 1.5

### Scenario: Ceph doesn't reach HEALTH_OK

1. **Stop** — Do not proceed to Phase 2
2. Check Ceph logs: `ceph health detail`
3. Verify network connectivity on VLAN 50 between all 3 nodes
4. Check disk health: `smartctl -a /dev/sdX` on japan
5. Consider if stale hardware is recoverable

### Scenario: Accidentally removed stale's OSDs too early

1. **Stop immediately** — Do not remove mon.stale
2. Verify data safety: `ceph health detail`
3. Continue with japan addition to restore capacity
4. Do not remove any more Ceph components until stable

### Scenario: proxmox_reset_ceph was accidentally set to true

1. **Do NOT run the playbook** — This will destroy all OSD data
2. Double-check `group_vars/proxmox.yml` before every playbook run
3. If already executed, stop immediately and assess damage

---

## Post-Validation Checklist

### Phase 1 Completion (Japan Added)

- [x] `ceph -s` shows **HEALTH_OK**
- [x] `pvecm status` shows 3 nodes: **method, indy, japan**
- [x] `ceph mon stat` shows 3 monitors: **mon.method, mon.indy, mon.japan**
- [x] `ceph osd tree` shows 9 OSDs with japan's 3 OSDs **up** and **in**
- [x] Network templates applied correctly with `dns-search bhamm-lab.com`
- [x] Question mark icon resolved in Proxmox GUI

### Phase 2 & 3 Pending (Remove stale, Update Configs)

- [ ] Remove stale from Ceph (OSDs, monitor)
- [ ] Remove stale from Proxmox cluster
- [ ] Clean up Ansible inventory (remove stale.yml, stale.j2)
- [ ] Update OpenTofu Talos configuration (stale → japan)
- [ ] Update Kubernetes manifests (replace 10.0.20.13 with 10.0.20.15)
- [ ] All VMs can migrate to and start on japan
- [ ] Kubernetes Talos workloads can access Ceph storage
- [ ] OpenTofu plan shows no drift for Talos cluster

---

## Timeline Estimate

### Completed (Actual)

| Phase | Step | Duration | Status |
|-------|------|----------|--------|
| 1.1 | Pre-flight verification | 5 minutes | ✅ Complete |
| 1.2 | Configure Ansible inventory | 30 minutes | ✅ Complete (multiple iterations) |
| 1.3 | Update storage role | 15 minutes | ✅ Complete (created LVM support, reverted to GPT) |
| 1.4 | Dry run | 5 minutes | ✅ Complete |
| 1.5 | Deploy via Ansible | 30-60 minutes | ✅ Complete (includes pmxcfs troubleshooting) |
| 1.6 | Post-deployment verification | 10 minutes | ✅ Complete |
| 1.7 | Wait for HEALTH_OK | 0 minutes | ✅ Complete (immediate HEALTH_OK) |
| Troubleshooting | FQDN/hosts fix | 20 minutes | ✅ Complete (dns-search, manual fixes) |

**Total Active Time:** ~2.5 hours
**Phase 1 Status:** ✅ COMPLETE

### Remaining (Phase 2 & 3)

| Phase | Step | Duration |
|-------|------|----------|
| 2.1-2.4 | Remove stale | 30 minutes |
| 2.5 | Cleanup inventory | 15 minutes |
| 3 | Update OpenTofu | 15 minutes |
| 3 | Update Kubernetes manifests | 30 minutes |

**Remaining Active Time:** ~1.5 hours
**Total Project Duration:** ~4 hours (actual)

---

## Notes

### Why Japan-First Strategy?

1. **Monitor Safety:** Adding mon.japan first restores 3-monitor quorum before removing stale's monitor
2. **Capacity:** Japan's 3 OSDs add ~6TB raw capacity before removing stale's dead OSDs
3. **Rollback:** If japan has issues, stale remains in configs for recovery

### LVM vs GPT Partitions

- **method, indy:** Continue using GPT partitions with separate `block.wal` and `block.db` partitions
- **japan:** Uses GPT partitions with `block.db` only (WAL colocated within DB partition)
- **Why not LVM:** pveceph's `osd create` command cannot use LVM logical volumes as `--db_dev` (resolves to `/dev/dm-X` which Proxmox can't identify)
- **Advantages of GPT:** Compatible with pveceph, persistent device naming via `/dev/disk/by-id/`
- **Why no separate WAL:** Modern BlueStore colocates WAL within the DB device efficiently when only `block.db` is specified

### Network Configuration Best Practices

1. **Always add `dns-search` to management interfaces** (VLAN 20) in `/etc/network/interfaces`
   - Prevents FQDN resolution issues (e.g., `japan.japan.bhamm-lab.com`)
   - Ensures Ansible's `ansible_fqdn` fact resolves correctly

2. **Use `/dev/disk/by-id/` paths for OSDs**
   - Handles device name shifts between reboots
   - Required for pveceph to correctly identify DB devices

3. **Ensure `/etc/hostname` contains short name only**
   - Should be `japan`, not `japan.bhamm-lab.com`
   - FQDN belongs in `/etc/hosts` and DNS

### Ansible Playbook Execution

The full deployment is a single playbook run:

```bash
ansible-playbook main.yml --limit japan --ask-pass --ask-become-pass
```

For subsequent runs (e.g., after initial bootstrapping when SSH keys are configured):

```bash
ansible-playbook main.yml --limit japan
```

The `--limit japan` flag is **critical** — it prevents the playbook from running against method and indy, which are live production nodes. Only japan should be targeted during Phase 1.

### IP Addressing

- japan uses **10.0.20.15** (aligned with IPMI at 10.0.10.25)
- All VLANs follow consistent pattern: 10.0.{VLAN}.15

---

## References

- Proxmox Cluster Manager: https://pve.proxmox.com/wiki/Cluster_Manager
- Proxmox Ceph Documentation: https://pve.proxmox.com/pve-docs/chapter-pveceph.html
- Ceph OSD Management: https://docs.ceph.com/en/latest/rados/operations/add-or-rm-osds/
- LVM for Ceph: https://docs.ceph.com/en/latest/rados/operations/bluestore-config-ref/
- lae.proxmox Ansible Role: https://github.com/lae/ansible-role-proxmox