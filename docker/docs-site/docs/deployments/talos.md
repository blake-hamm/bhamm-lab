# Talos
When deploying talos, we leverage open tofu which orchestates the following steps:
- Curl talos schematic id given version and schematic
- Download given schematic id to proxmox
- Deploy master/worker vms
- Configure talos
- Deploy bootstrap charts (metallb, cilium and ceph)


To deploy talos run these commands:
```bash
# First deploy vm's and bootstrap the cluster
tofu -chdir=tofu/proxmox/talos init
tofu -chdir=tofu/proxmox/talos workspace select -or-create=true green
tofu -chdir=tofu/proxmox/talos plan -var-file=green.tfvars
tofu -chdir=tofu/proxmox/talos apply -var-file=green.tfvars -auto-approve

# Then deploy the minimum required for kubernetes
export KUBECONFIG=../../tofu/proxmox/talos/result/kube-config-green.yaml
export KUBE_CONFIG_PATH=../../tofu/proxmox/talos/result/kube-config-green.yaml
tofu -chdir=tofu/kubernetes init
tofu -chdir=tofu/kubernetes workspace select -or-create=true green
tofu -chdir=tofu/kubernetes plan -var 'environment=green' -var 'branch_name=feature/refactor-cluster'
tofu -chdir=tofu/kubernetes apply -var 'environment=green' -var 'branch_name=feature/refactor-cluster' -auto-approve

# To destroy
tofu -chdir=tofu/proxmox/talos destroy -var-file=dev.tfvars -auto-approve
```

```bash
export KUBECONFIG=./tofu/proxmox/talos/result/kube-config-green.yaml
kubectl config set-context --current --namespace=argocd
argocd app get apps-green --refresh
```