Before running OpenTofu, ensure Proxmox host storage is configured via Ansible. The `storage` role configures LVM (`local-vg`) and swap automatically when running the Ansible playbook. If the host has a dedicated VM drive, ensure the host's `storage_vm_device` variable is set correctly in `ansible/inventory/host_vars/<hostname>.yml` — for `method` this is set to `/dev/disk/by-id/ata-Samsung_SSD_870_EVO_1TB_S75BNL0Y201685W`. For single-drive hosts (`indy`, `japan`), leave `storage_vm_device` empty.

```bash
# To configure proxmox tofu
tofu -chdir=tofu/proxmox/config init
tofu -chdir=tofu/proxmox/k3s workspace select default
tofu -chdir=tofu/proxmox/config plan
tofu -chdir=tofu/proxmox/config apply

# To run ansible playbooks targeted for proxmox
ansible-playbook ansible/main.yml -l proxmox -t debian,proxmox
```