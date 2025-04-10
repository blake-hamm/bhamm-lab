# Talos
When deploying talos, we leverage open tofu which orchestates the following steps:
- Curl talos schematic id given version and schematic
- Download given schematic id to proxmox
- Deploy master/worker vms
- Configure talos
- Deploy bootstrap charts (metallb, cilium and ceph)


To deploy talos run these commands:
```bash
tofu -chdir=tofu/proxmox/talos init
tofu -chdir=tofu/proxmox/talos workspace select -or-create=true dev
tofu -chdir=tofu/proxmox/talos plan -var-file=dev.tfvars
tofu -chdir=tofu/proxmox/talos apply -var-file=dev.tfvars -parallelism=1 -auto-approve

# To destroy
tofu -chdir=tofu/proxmox/talos destroy -var-file=dev.tfvars -auto-approve
```