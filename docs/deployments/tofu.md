# Open Tofu (Terraform)
```bash
tofu -chdir=tofu/proxmox/k3s init
tofu -chdir=tofu/proxmox/k3s apply -parallelism=2 -auto-approve
```
