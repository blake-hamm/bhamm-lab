```bash
# To configure proxmox tofu
tofu -chdir=tofu/proxmox/config init
tofu -chdir=tofu/proxmox/config plan

# To run ansible playbooks targeted for proxmox
ansible-playbook ansible/main.yml -l proxmox -t debian,proxmox
```