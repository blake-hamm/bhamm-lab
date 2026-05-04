Before running OpenTofu, ensure Proxmox host storage is configured via Ansible. The `storage` role configures LVM (`local-vg`) and swap automatically when running the Ansible playbook. Each host has a dedicated VM storage device set via `storage_vm_device` in `ansible/inventory/host_vars/<hostname>.yml`:

- `method`: `/dev/disk/by-id/nvme-SHGP31-1000GM-2_AS0CN42841190CT25`
- `indy`: `/dev/disk/by-id/nvme-Sabrent_Rocket_4.0_Plus_A5CD0712179183364499`
- `japan`: `/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_25286M804502`

```bash
# To configure proxmox tofu
tofu -chdir=tofu/proxmox/config init
tofu -chdir=tofu/proxmox/k3s workspace select default
tofu -chdir=tofu/proxmox/config plan
tofu -chdir=tofu/proxmox/config apply

# To run ansible playbooks targeted for proxmox
ansible-playbook ansible/main.yml -l proxmox -t debian,proxmox
```