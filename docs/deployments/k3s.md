# k3s deployment
To spin up a kubernetes cluster in bhamm-lab, you need to follow these steps:
1. Terraform to spin up vm's
```bash
tofu -chdir=tofu/proxmox/k3s apply -parallelism=2 -auto-approve
```
*Note: This command will also destroy and replace existing vm's*
2. Ansible to secure debian vm's and deploy k3s
```bash
ansible-playbook ansible/main.yml -l k3s*
```
*Note: this uses proxmox dynamic inventory*
3. Argocd to deploy app of apps and restore services
```bash
kubectl apply -f kubernetes/argocd-prod.yaml
```
*Note: you may need to adjust the 'targetRevision' in this file*
