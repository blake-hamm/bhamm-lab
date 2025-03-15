# k3s deployment
To spin up a kubernetes cluster in bhamm-lab, you need to follow these steps:
1. Terraform to spin up vm's
```bash
tofu -chdir=tofu/proxmox/k3s init
tofu -chdir=tofu/proxmox/k3s workspace select dev
tofu -chdir=tofu/proxmox/k3s plan -var-file=dev.tfvars
tofu -chdir=tofu/proxmox/k3s apply -var-file=dev.tfvars -parallelism=2 -auto-approve

# To destroy
tofu -chdir=tofu/proxmox/k3s destroy -var-file=dev.tfvars -parallelism=2 -auto-approve
```
*Note: This command will also destroy and replace existing vm's*

2. Ansible to secure debian vm's and deploy k3s
```bash
ansible-playbook ansible/main.yml -l dev-k3s* -t debian,k3s -e "env=dev"
```
*Note: this uses proxmox dynamic inventory*

3. Argocd to deploy app of apps and restore services
```bash
# To deploy the dev
export KUBECONFIG=~/.kube/config-dev
kubectl apply -f kubernetes/dev.yaml

# To sync the argocd app (it should autosync, but if impatient)
kubectl config set-context --current --namespace=argocd
argocd app sync apps-dev
argocd app get apps-dev --refresh
```
*Note: you may need to adjust the 'targetRevision' in this file*
