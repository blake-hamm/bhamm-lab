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

**Single-drive hosts** (`indy`, `japan`):
- Root LV is resized to 100GB (`storage_root_size`)
- Root VG is renamed from `<hostname>-vg` to `local-vg`
- Swap LV is configured to 4GB (`storage_swap_size`)
- Remaining space in `local-vg` is used for Proxmox VM storage

**Separate VM drive host** (`method`):
- Boot drive keeps its original VG name (`method-vg`) with root at 100GB and swap at 4GB
- A dedicated 1TB SSD (set via `storage_vm_device` in host vars) creates a separate `local-vg` for VM storage

**Why `local-vg`?**
- Downstream Terraform and the `lae.proxmox` role reference `local-vg` when provisioning VMs. Consistent naming avoids per-host logic.

**Host variables:**
- `storage_vm_device`: Set to a block device path for separate VM drive mode; leave empty for single-drive mode
- `storage_root_size`: Root LV size (default: `100g`)
- `storage_swap_size`: Swap LV size (default: `4g`)

**Important:** Do not manually create volume groups or resize LVs before running Ansible. The role is idempotent and handles all LVM configuration automatically.

## Proxmox
Configured with this role: https://github.com/lae/ansible-role-proxmox . Adjust the `ansible/inventory/group_vars/proxmox.yml` file accordingly and ensure a new host is in the `proxmox` group.
