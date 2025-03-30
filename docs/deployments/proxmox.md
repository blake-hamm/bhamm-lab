```bash
# To configure proxmox tofu
tofu -chdir=tofu/proxmox/config init
tofu -chdir=tofu/proxmox/k3s workspace select default
tofu -chdir=tofu/proxmox/config plan
tofu -chdir=tofu/proxmox/config apply

# To run ansible playbooks targeted for proxmox
ansible-playbook ansible/main.yml -l proxmox -t debian,proxmox
```