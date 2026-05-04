# Ansible
```bash
# To run "main.yaml"
ansible-playbook ansible/main.yaml
```

## Bootstrap new machine
These steps will bootstrap and configure a new debian host.

1. Manually install the latest version of debian on the host
  - Skip the root user and create a `bhamm` user
  - Give a relevant hostname and domain of `bhamm-lab.com`
  - Disable a DE and enable ssh and utils
2. After rebooting, check the ip address of the host with `ip a`
3. Create a new record in the `ansible/inventory/hosts` file and use the bootstrap args
4. Be intentional and configure the `ansible/templates/<hostname>.j2` file carefully to build the desired network state
5. Run on framework machine:
  - `ansible-playbook ansible/main.yml --ask-pass --ask-become-pass`
6. Once this completes, you can remove bootstrap args and the machine should be good to got

## Storage configuration

During bootstrap, the `storage` role runs automatically as part of the `debian` playbook.

It handles LVM setup for Proxmox hosts in two modes:

**All Proxmox hosts** (`method`, `indy`, `japan`) use dedicated boot drives with separate VM storage:
- Boot drive keeps its original VG name (`<hostname>-vg`) with root at 100GB and swap at 4GB
- A second `local-vg` is created on the dedicated VM storage device for Proxmox VM disks

**Host-specific VM storage:**
- `method`: 1TB NVMe (`/dev/disk/by-id/nvme-SHGP31-1000GM-2_AS0CN42841190CT25`)
- `indy`: 1TB NVMe (`/dev/disk/by-id/nvme-Sabrent_Rocket_4.0_Plus_A5CD0712179183364499`)
- `japan`: 1TB NVMe (`/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502`)

**Legacy single-drive mode** (no longer used):
- Root VG (`<hostname>-vg`) is renamed to `local-vg`
- Root LV is capped at 100GB, swap at 4GB; remaining space hosts VMs

**Why `local-vg`?**
- Downstream Terraform and the `lae.proxmox` role reference `local-vg` when provisioning VMs. Consistent naming avoids per-host logic.

**Host variables:**
- `storage_vm_device`: Set to a block device path for separate VM drive mode; leave empty for single-drive mode
- `storage_root_size`: Root LV size (default: `100g`)
- `storage_swap_size`: Swap LV size (default: `4g`)

**Important:** Do not manually create volume groups or resize LVs before running Ansible. The role is idempotent and handles all LVM configuration automatically.

## Proxmox
Configured with this role: https://github.com/lae/ansible-role-proxmox . Adjust the `ansible/inventory/group_vars/proxmox.yml` file accordingly and ensure a new host is in the `proxmox` group.
