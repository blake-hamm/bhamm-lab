# Terraform

## Commands
To apply:
```bash
terraform -chdir=terraform destroy
```

## Libvirt
Currently, libvirt is not used. It was experimental to see if libvirt could be used directly on nixos. The terraform libvirt module has very limited support and I had difficulty launching an opnsense vm and troubleshooting it. We will go with proxmox instead because there are more features and support.
