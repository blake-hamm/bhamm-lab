# AGENTS.md - Coding Guidelines for bhamm-lab

This repository is a infrastructure monorepo for managing homelab infrastructure across Proxmox, Kubernetes, NixOS, and cloud providers.

## Project Structure

```
.
├── ansible/          # Ansible playbooks and inventory for configuring Proxmox and opensense
├── docker/           # Custom container images
├── kubernetes/       # K8s manifests and Helm charts
├── nix/              # NixOS configurations and modules
├── tofu/             # OpenTofu/Terraform infrastructure
└── scripts/          # Utility scripts
```

---

## Important Notes

- **Never** commit any code; I will always have the last say
- **Never** run critical commands like tofu apply or ansible-playbook
- Always run linters before committing
- The dev shell auto-installs ansible requirements and pre-commit hooks
