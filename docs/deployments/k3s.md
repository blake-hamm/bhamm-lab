# k3s deployment
To spin up a kubernetes cluster in bhamm-lab, you need to follow these steps:
1. Terraform to spin up vm's
```bash
tofu -chdir=tofu/proxmox/k3s init
tofu -chdir=tofu/proxmox/k3s workspace select -or-create=true dev
tofu -chdir=tofu/proxmox/k3s plan -var-file=dev.tfvars
tofu -chdir=tofu/proxmox/k3s apply -var-file=dev.tfvars -parallelism=2 -auto-approve

# To destroy
tofu -chdir=tofu/proxmox/k3s destroy -var-file=dev.tfvars -parallelism=2 -auto-approve
```
*Note: This command will also destroy and replace existing vm's*

2. Ansible to secure debian vm's and deploy k3s
```bash
# To deploy k3s dev from the ground up
ansible-playbook ansible/main.yml -l dev-k3s* -t debian,k3s -e "env=dev BRANCH_NAME=main"

# In case you want to just pull local kube config
ansible-playbook ansible/main.yml -l dev-k3s* -t kubeconfig -e "env=dev k3s_force_deploy=true" --skip-tags debian

# In case you need to sync argocd on the cli
export KUBECONFIG=~/.kube/config-dev
kubectl config set-context --current --namespace=argocd
argocd app get apps-dev --refresh
argocd app sync apps-dev --prune
argocd app terminate-op apps-dev
```
*Note: this uses proxmox dynamic inventory*
