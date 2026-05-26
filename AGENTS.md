# AGENTS.md - Coding Guidelines for bhamm-lab

This repository is an infrastructure monorepo for managing homelab infrastructure across Proxmox, Kubernetes, NixOS, and cloud providers.

## Architecture Primer

Key infrastructure facts. When in doubt, verify against the actual code — not these summaries.

- **Storage chain:** Ceph RGW (primary S3, on Proxmox) → Garage (local mirror, NixOS VM on Proxmox `japan`) → Backblaze B2 (primary offsite). Cloudflare R2 is standby restore-only.
- **Kubernetes:** Talos Linux, ephemeral blue/green clusters, GitOps via ArgoCD.
- **Hypervisors:** Proxmox on Debian, configured via Ansible. VMs provisioned with OpenTofu (`tofu/`).
- **Secrets:** SOPS encrypted with GCP KMS, synced to Vault via Argo Workflows.
- **Docs site:** `docker/docs-site/docs/` (mkdocs, material theme) — mirrors deployed state. Keep in sync with infrastructure changes.

## Project Structure

```
.
├── ansible/          # Ansible playbooks and inventory for configuring Proxmox and OPNsense
├── docker/           # Container images, docs-site (mkdocs), and personal site (Hugo)
├── kubernetes/       # K8s manifests and Helm charts
├── nix/              # NixOS configurations and modules
├── tofu/             # OpenTofu/Terraform infrastructure
└── scripts/          # Utility scripts
```

---

# Implementation Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## Docs Site

When changing infrastructure code (ansible roles, tofu configs, k8s manifests, nix modules), check whether `docker/docs-site/docs/` needs a corresponding update.

## Important Notes

- **Never** commit any code; I will always have the last say
- **Never** run critical commands like `tofu apply` or `ansible-playbook`
- Always run linters before committing
- Pre-commit runs: `nixpkgs-fmt`, `yamlfmt` (Google), `shfmt`, `ansible-lint` (ansible/ only), `terraform_fmt` + `tflint` + `trivy`, `gitleaks` + `ripsecrets` (dual secret scanning), `trailing-whitespace`, `mixed-line-ending`, `forbid-tabs` (2-space indent)
- The dev shell auto-installs ansible requirements and pre-commit hooks
