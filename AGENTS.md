# AGENTS.md - Coding Guidelines for bhamm-lab

This repository is a NixOS/infrastructure monorepo for managing homelab infrastructure across Proxmox, Kubernetes, NixOS, and cloud providers.

## Project Structure

```
.
├── ansible/          # Ansible playbooks and inventory
├── docker/           # Custom container images
├── kubernetes/       # K8s manifests and Helm charts
├── nix/              # NixOS configurations and modules
├── tofu/             # OpenTofu/Terraform infrastructure
├── site/             # Documentation site (MkDocs)
└── scripts/          # Utility scripts
```

## Architecture Overview

### Hardware
- **Servers:** 5 servers – 'Method' (SuperMicro H12SSL-i), 'Indy' (SuperMicro D-2146NT), 'Stale' (X10SDV-4C-TLN4F), 'Nose' & 'Tail' (Framework)
- **SBCs:** Orange Pi Zero3 (Pi-hole DNS), Raspberry Pi 4 (PiKVM)
- **Networking:** TP-Link Omada switches & Protectli OPNsense firewall
- **Accelerated Compute:** Intel Arc A310, AMD Radeon AI Pro R9700, AMD Ryzen AI MAX+ 395 (Strix Halo)

### Software Stack
- **Operating Systems:** Debian, Proxmox, Talos, NixOS, TrueNAS
- **Container Orchestration:** Talos Kubernetes clusters (blue/green), Harbor registry
- **Storage:** Ceph (hot), SeaweedFS (S3), TrueNAS/MinIO (cold), Cloudflare R2 (offsite)
- **Automation:** OpenTofu, Ansible, ArgoCD, Argo Events/Workflows
- **Security:** SOPS, HashiCorp Vault, Authelia (OIDC), Traefik, Cert Manager
- **Observability:** Prometheus/Grafana, Loki, Alertmanager

## Development Environment

Enter the Nix dev shell (installs all dependencies):
```bash
nix develop
```

## Build/Lint/Test Commands

### Pre-commit (runs all linters)
```bash
# Run on all files
pre-commit run --all-files

# Run on staged files only
pre-commit run

# Run specific hook
pre-commit run nixpkgs-fmt
pre-commit run ansible-lint
pre-commit run terraform_fmt
```

### Nix

#### Host Discovery & Generator Pattern
This flake uses a unique **automatic host discovery** system via `nix/lib/generators.nix`:
- Hosts are auto-discovered from `nix/hosts/` directories containing a `deploy` attribute
- The generator creates both `nixosConfigurations` and Colmena deployments automatically
- Supports per-host architecture (x86_64-linux or aarch64-linux) via `system` attribute

**Host configuration example:**
```nix
# nix/hosts/<hostname>/default.nix
{
  system = "x86_64-linux";  # Optional, defaults to x86_64-linux

  deploy = {
    tags = [ "server" "framework" ];
    targetHost = "10.0.30.79";
    allowLocalDeployment = true;  # Optional, for local machine
  };

  imports = [
    ./hardware-configuration.nix
    ./../../profiles/server.nix
  ];

  # Host-specific configuration
  cfg.framework.enable = true;
}
```

#### Common Commands
```bash
# Format Nix files
nixpkgs-fmt .

# Check flake
nix flake check

# Build NixOS configuration
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel

# Deploy with colmena
colmena apply
colmena apply --on <hostname> --impure
colmena apply-local --sudo

# Update flake
nix flake update

# Build ISO
nix build .#nixosConfigurations.minimal-iso.config.system.build.isoImage
```

### Ansible
```bash
# Run playbook
ansible-playbook ansible/main.yml

# Run with specific tags
ansible-playbook ansible/main.yml --tags debian

# Run for specific host
ansible-playbook ansible/main.yml --limit method

# Bootstrap new machine (first run)
ansible-playbook ansible/main.yml --ask-pass --ask-become-pass

# Lint
ansible-lint ansible/

# Install dependencies
ansible-galaxy install -r ansible/requirements.yml

# Create new role
ansible-galaxy role init <role-name>
```

### Terraform/OpenTofu

#### Talos Kubernetes Deployment
```bash
# Deploy Talos cluster
cd tofu/proxmox/talos
tofu init
tofu workspace select -or-create=true blue
tofu plan -var-file=blue.tfvars
tofu apply -var-file=blue.tfvars

# Deploy Kubernetes bootstrap (Cilium, Ceph, etc.)
export KUBECONFIG=../../tofu/proxmox/talos/result/kube-config-blue.yaml
export KUBE_CONFIG_PATH=$KUBECONFIG
cd tofu/kubernetes
tofu init
tofu workspace select -or-create=true blue
tofu plan -var 'environment=blue' -var 'branch_name=main'
tofu apply -var 'environment=blue' -var 'branch_name=main'

# Destroy cluster
export KUBECONFIG=./tofu/proxmox/talos/result/kube-config-blue.yaml
argo submit --from workflowtemplate/kill-switch --namespace argo \
  --serviceaccount workflow-admin --entrypoint cleanup
tofu -chdir=tofu/proxmox/talos destroy -var-file=blue.tfvars
```

#### General Commands
```bash
cd tofu/<module>

# Format
tofu fmt

# Validate
tofu validate

# Lint
tflint

# Security scan
trivy filesystem .
```

### Kubernetes
```bash
# Validate manifests
kubectl apply --dry-run=client -f kubernetes/<path>

# Lint with kubeval/kubeconform (if installed)
kubeconform -strict kubernetes/

# Talos specific
export TALOSCONFIG=./tofu/proxmox/talos/result/talos-config-blue.yaml
talosctl dashboard
talosctl -n <ip> get disks -o yaml
talosctl -n <ip> reset  # Remove node from cluster

# ArgoCD
argocd app get <app-name> --refresh
```

### Ceph Operations
```bash
# Create CSI credentials
ceph auth get-or-create client.k8s-rbd
ceph auth caps client.k8s-rbd \
  mon 'allow r' \
  osd 'allow class-read object_prefix rbd_children, allow rwx pool=osd' \
  mgr 'allow *'

ceph auth get-or-create client.k8s-cephfs
ceph auth caps client.k8s-cephfs \
  mon 'allow r' \
  mds 'allow *' \
  osd 'allow rwx pool=cephfs_metadata, allow rwx pool=cephfs_data' \
  mgr 'allow *'
```

## Code Style Guidelines

### Nix
- Use `nixpkgs-fmt` for formatting (enforced by pre-commit)
- Prefer `let ... in` over nested `with` statements
- Use `inherit` for passing variables: `inherit pkgs inputs;`
- Function arguments: use `@inputs` pattern for destructuring
- 2-space indentation
- snake_case for variable names
- Supports both x86_64-linux and aarch64-linux architectures

### Ansible
- YAML: 2-space indentation
- Use descriptive task names
- Tag all tasks appropriately
- Use `ansible-lint` rules (see `.ansible-lint`)
- Inventory: define hosts with `ansible_host` variables
- Encrypted values use SOPS (see `.sops.yaml`)

### Terraform/OpenTofu
- Run `tofu fmt` before committing
- Use semantic versioning for module sources
- Pin provider versions
- Organize resources logically (compute/, network/, storage/)
- Use workspaces for environment separation (blue/green)

### Kubernetes YAML
- Use yamlfmt (enforced by pre-commit)
- 2-space indentation
- Include resource requests/limits
- Use namespaces consistently
- Label all resources with `app:` label
- Add ArgoCD sync-wave annotations where needed

### Shell Scripts
- Use `shfmt` for formatting
- Use 2-space indentation
- Include shebang (`#!/bin/bash` or `#!/bin/sh`)
- All scripts must be executable
- Use `set -e` for error handling

### Python
- Follow PEP 8
- Use type hints where appropriate
- Use `uv` or `poetry` for dependency management
- Import order: stdlib → third-party → local

## Naming Conventions

- **Files**: kebab-case (e.g., `hardware-config.nix`)
- **Variables**: snake_case (e.g., `ssh_port`)
- **Hosts**: lowercase (e.g., `method`, `indy`)
- **Secrets**: `*.enc.yaml`, `*.enc.json`
- **Workspaces**: blue/green for environment separation

## Secrets Management

- Use SOPS for all secrets (GCP KMS + age key)
- Never commit unencrypted secrets
- Encrypted files: `*.enc.yaml`, `*.enc.json`
- Decrypted temp files: `*.decrypted.*` (gitignored)
- SOPS changes trigger sync to HashiCorp Vault via Argo workflows

```bash
# Encrypt file
sops -e -i secrets.yaml

# Decrypt file
sops -d secrets.enc.yaml > secrets.decrypted.yaml

# Edit encrypted file
sops secrets.enc.yaml
```

## CI/CD and GitOps

- **Primary:** Argo Events/Workflows triggered from Forgejo webhooks
- **GitOps:** ArgoCD manages 100% of cluster applications (App-of-Apps pattern)
- **Container Builds:** Automatic builds on changes to `docker/` directories
- **Docs:** MkDocs deployment on changes

## Testing

- Run `pre-commit run --all-files` before commits
- Validate Nix expressions: `nix-instantiate --eval <file>`
- Test Ansible playbooks in check mode: `--check --diff`
- Test Terraform plans: `tofu plan`

## Git Workflow

- Use conventional commit messages
- Keep commits atomic and focused
- Pre-commit hooks must pass before pushing
- Protected branches: `main`

## Important Notes

- **Never** commit `.env` files or decrypted secrets
- Always run linters before committing
- The dev shell auto-installs ansible requirements and pre-commit hooks
- SOPS uses GCP KMS for key management
- Backup workflow: PVCs → SeaweedFS → MinIO (TrueNAS) → Cloudflare R2
- Pi-hole runs on Orange Pi Zero3 (aarch64) with NixOS
