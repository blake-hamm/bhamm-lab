# Open Tofu (Terraform)
```bash
# To migrate state
tofu -chdir=tofu/proxmox/k3s init -migrate-state
tofu -chdir=tofu/proxmox/k3s apply -parallelism=2 -auto-approve
```
