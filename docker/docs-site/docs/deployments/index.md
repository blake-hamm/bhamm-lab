# Deployments

*Central hub for infrastructure and application deployment procedures; mainly for my reference.*

## Core Workflows
- **Automated CI/CD**: Primary deployment path for routine changes using Argo Events and Workflows triggered from Forgejo webhook
- **Manual Operations**: For newer capabilities or configuring bare metal

## Key References
- 🔧 [Ansible Playbooks](ansible.md) - Debian and Opnsense configuration management
- ☁️ [Cloud Provisioning (GCP)](gcp.md) - Cloud infrastructure setup with Open Tofu
- 🖥️ [On-Prem (Proxmox)](proxmox.md) - Hypervisor setup with Ansible and Open Tofu
- 🛳️ [Common Helm Chart](helm.md) - Common kubernetes application deployments
- 📦 [NixOS Configs](nixos.md) - Declarative OS configurations for Framework 13 laptop
- 🤖 [Talos](talos.md) - Kubernetes OS deployment and management with Open Tofu
- 📘 [Docs (MkDocs)](mkdocs.md) - Documentation deployment
- ⚠️ Deprecated: [k3s](k3s.md) - Use Talos instead

## Recovery Procedures
- Rollback workflows covered in relevant tool docs
- Post-deployment validation standards
