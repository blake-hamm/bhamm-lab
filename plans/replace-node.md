# Replace 'stale' Node with 'japan' Node

## Executive Summary

This plan replaces the dead 'stale' node (10.0.20.13) with a new 'japan' node (10.0.20.15) in the Proxmox/Ceph cluster.

**Critical Strategy:** Japan is added *first* to restore monitor quorum and add capacity *before* formally removing stale. This minimizes risk during the degraded state.

**Current State:** Ceph HEALTH_WARN (31.8% degraded), 2/3 monitors up, osd.2 & osd.5 down on stale
**Target State:** Ceph HEALTH_OK, 3 monitors up, japan contributing 3 new OSDs

**Automation Strategy:** All of Phase 1 (Proxmox install, cluster join, Ceph deployment) is handled by Ansible using the `lae.proxmox` role. The `lae.proxmox` role supports Ceph monitor creation, OSD creation with DB/WAL devices, and cluster joining — no GUI or manual CLI steps needed. Phase 2 (removal) is manual since `lae.proxmox` only supports creation, not destruction.

---

## Hardware Architecture

### Transplant to japan

| Device | Source | Purpose |
|--------|--------|---------|
| 1TB NVMe | NEW | Proxmox boot drive |
| 1TB NVMe | stale (salvaged) | Ceph DB/WAL device (vg_ceph_db) |
| 1TB EVO SSD | stale (salvaged) | OSD.0 (with LVM DB) |
| 3.84TB SSD | stale (salvaged) | OSD.1 (with LVM DB) |
| 1TB EVO SSD | Extra inventory | OSD.2 (with LVM DB) |

### Network Configuration (japan)

| Interface | Usage | IP Address | VLAN |
|-----------|-------|------------|------|
| enp1s0f0 | Trunk (metal + k8s) | 10.0.20.15/24, 10.0.30.15/24 | 20, 30 |
| enp1s0f1 | Ceph private | 10.0.50.15/24 | 50 |

### Ceph OSD Mapping (Post-Deployment)

| OSD | Device | DB Location | Size | Source |
|-----|--------|-------------|------|--------|
| osd.6 | /dev/sda | /dev/vg_ceph_db/osd1_db | 40g DB | 1TB EVO (stale) |
| osd.7 | /dev/sdb | /dev/vg_ceph_db/osd2_db | 40g DB | 1TB EVO (extra) |
| osd.8 | /dev/sdc | /dev/vg_ceph_db/osd3_db | 160g DB | 3.84TB (stale) |

---

## Phase 1: Add japan to Cluster (Pre-Removal)

### Step 1.1: Pre-flight Verification

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

# Ceph config for proxmox — LVM method (new)
ceph_nvme_device: /dev/nvme0n1
ceph_vg_name: vg_ceph_db
ceph_partitions:
  - name: osd1_db
    size: 40g
  - name: osd2_db
    size: 40g
  - name: osd3_db
    size: 160g

# Proxmox config
pve_ceph_osds:
  - device: /dev/sda
    block.db: /dev/vg_ceph_db/osd1_db
    crush.device.class: ssd
  - device: /dev/sdb
    block.db: /dev/vg_ceph_db/osd2_db
    crush.device.class: ssd
  - device: /dev/sdc
    block.db: /dev/vg_ceph_db/osd3_db
    crush.device.class: ssd
```

Note: Unlike method/indy which use GPT partitions with separate `block.wal`, japan uses LVM logical volumes with `block.db` only (WAL is colocated within the DB LV). This is a design improvement — LVM provides persistent device naming and dynamic sizing, and modern BlueStore performs well with colocated WAL.

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
    mtu 9000

# Kubernetes interface on VLAN 30 via the bridge:
auto vmbr0.30
iface vmbr0.30 inet static
    address 10.0.30.15/24
    netmask 255.255.255.0
    dns-nameservers 10.0.9.2
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

### Step 1.3: Update Storage Role for LVM Support (Backward Compatible)

**Modify:** `ansible/roles/storage/tasks/main.yml`

Replace the proxmox storage include block:

```yaml
- name: Extra config for Proxmox storage (LVM method)
  ansible.builtin.include_tasks:
    file: proxmox-lvm.yml
  when: "'proxmox' in group_names and ceph_vg_name is defined"

- name: Extra config for Proxmox storage (GPT partition method)
  ansible.builtin.include_tasks:
    file: proxmox.yml
  when: "'proxmox' in group_names and ceph_vg_name is not defined"
```

**Create:** `ansible/roles/storage/tasks/proxmox-lvm.yml`

```yaml
- name: Ensure NVMe drive is initialized as an LVM Volume Group
  community.general.lvg:
    vg: "{{ ceph_vg_name }}"
    pvs: "{{ ceph_nvme_device }}"
    state: present

- name: Create Ceph DB logical volumes
  community.general.lvol:
    vg: "{{ ceph_vg_name }}"
    lv: "{{ item.name }}"
    size: "{{ item.size }}"
    state: present
  loop: "{{ ceph_partitions }}"

- name: Load FUSE kernel module
  community.general.modprobe:
    name: fuse
    persistent: "present"
    state: present
```

**Backward compatibility:** method and indy do NOT define `ceph_vg_name`, so they will continue using the GPT partition method (`proxmox.yml`). Only japan (which defines `ceph_vg_name`) uses the new LVM method.

### Step 1.4: Dry Run

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

### Step 1.5: Deploy japan via Ansible

Japan must be reachable via SSH before running the playbook. Use password auth for the initial connection:

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

### Step 1.6: Post-Deployment Verification

After the playbook completes, verify the cluster from method or indy:

```bash
# Verify japan joined the cluster
pvecm status
# Should show: method, indy, japan (3 nodes)

# Verify monitor quorum restored
ceph mon stat
# Should show 3+ monitors (method, indy, stale-down, japan)
# Note: mon.stale may still appear in the map even though it's down

# Verify OSDs are up
ceph osd tree
# Should show osd.6, osd.7, osd.8 as "up" and "in" on japan

# Check cluster health
ceph -s
# Expect HEALTH_WARN initially (backfilling/rebalancing)
```

### Step 1.7: Wait for Ceph Recovery

**Monitor cluster health:**

```bash
watch -n 5 ceph -s
```

**Expected indicators:**
- Health will show HEALTH_WARN initially (backfilling)
- Degraded percentage will decrease over time
- Recovery rate will be displayed

**CRITICAL:** Do not proceed to Phase 2 until:
- `ceph -s` shows **HEALTH_OK**
- All PGs show **active+clean**

**Typical duration:** 2-6 hours depending on data volume

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

After completion, verify all items:

- [ ] `ceph -s` shows **HEALTH_OK**
- [ ] `pvecm status` shows 3 nodes: **method, indy, japan**
- [ ] `ceph mon stat` shows 3 monitors: **mon.method, mon.indy, mon.japan**
- [ ] `ceph osd tree` shows 6+ OSDs with japan's 3 OSDs **up** and **in**
- [ ] All VMs can migrate to and start on japan
- [ ] Kubernetes Talos workloads can access Ceph storage
- [ ] Network templates applied correctly (VLANs 20, 30, 50)
- [ ] OpenTofu plan shows no drift for Talos cluster
- [ ] `ansible-playbook main.yml --limit japan --check` shows no unexpected changes

---

## Timeline Estimate

| Phase | Step | Duration |
|-------|------|----------|
| 1.1 | Pre-flight verification | 5 minutes |
| 1.2-1.3 | Create config files | 15 minutes |
| 1.4 | Dry run | 5 minutes |
| 1.5 | Deploy via Ansible | 30-60 minutes (includes reboot) |
| 1.6 | Post-deployment verification | 10 minutes |
| 1.7 | Wait for HEALTH_OK | **2-6 hours** |
| 2.1-2.4 | Remove stale | 30 minutes |
| 2.5 | Cleanup inventory | 15 minutes |
| 3 | Update OpenTofu | 15 minutes |

**Total Active Time:** ~1.5 hours
**Total Duration (including backfill):** 3-7 hours

---

## Notes

### Why Japan-First Strategy?

1. **Monitor Safety:** Adding mon.japan first restores 3-monitor quorum before removing stale's monitor
2. **Capacity:** Japan's 3 OSDs add ~6TB raw capacity before removing stale's dead OSDs
3. **Rollback:** If japan has issues, stale remains in configs for recovery

### LVM vs GPT Partitions

- **method, indy:** Continue using legacy GPT partitions (backward compatible — `ceph_vg_name` is not defined, so they use `proxmox.yml`)
- **japan:** Uses new LVM approach with `ceph_vg_name` defined, routing to `proxmox-lvm.yml`
- **Advantages of LVM:** Persistent device naming (no `/dev/disk/by-id/...-partN`), dynamic sizing, cleaner management
- **LVM volumes** do not need separate WAL partitions — modern BlueStore colocates WAL within the DB device efficiently

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