---
title: "Homelab"
weight: 5
---

#### [docs.bhamm-lab.com](https://docs.bhamm-lab.com/) · [github.com/blake-hamm/bhamm-lab](https://github.com/blake-hamm/bhamm-lab)

A homelab built for AI/ML experimentation, DevOps exploration, and self-hosting — documented as infrastructure-as-code in a monorepo.

**Hardware:** 6 servers across SuperMicro, Framework mainboards, and custom builds, with a Ceph storage backbone, dual 10GbE networking, and accelerated compute (AMD Radeon AI Pro R9700, Intel Arc A310, dual AMD Ryzen AI MAX+ 395).

**Software Stack:** Ephemeral Talos Kubernetes clusters managed via ArgoCD + OpenTofu provisioning. Debian/Proxmox hosts configured with Ansible. NixOS for workstations. Ceph RGW + Garage for storage.

**AI/ML:** Llama.cpp inference scaled to zero with KubeElasti, routed through LiteLLM. GPU orchestration via Intel GPU plugin and AMD ROCm operator. Embedding inference on AMD Radeon, dense/MoE inference on dual Strix Halo systems.

**Key Practices:** GitOps deployments, 3-2-1 backup strategy with Argo Workflows + Backblaze B2 offsite (Cloudflare R2 standby), SOPS + Vault for secrets, network segmentation with OPNsense + Pi-hole DNS, automated disaster recovery with blue/green cluster testing.

The full docs site covers [architecture](https://docs.bhamm-lab.com/architecture/), [deployments](https://docs.bhamm-lab.com/deployments/), [operations](https://docs.bhamm-lab.com/operations/), [AI/ML](https://docs.bhamm-lab.com/ai/), [backups](https://docs.bhamm-lab.com/backups/), and [security](https://docs.bhamm-lab.com/security/).
