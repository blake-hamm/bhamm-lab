# bhamm-lab

<!--![Architecture Diagram](docker/docs-site/docs/assets/diagram.png)-->
[![GitHub stars](https://img.shields.io/github/stars/blake-hamm/bhamm-lab?style=social)](https://github.com/blake-hamm/bhamm-lab/stargazers) [![License](https://img.shields.io/github/license/blake-hamm/bhamm-lab)](LICENSE.md)

A comprehensive self‑hosted homelab environment designed for AI/ML workloads, DevOps experimentation and security research.

- [Overview](#overview)
- [Core Infrastructure](#core-infrastructure)
- [Key Features](#key-features)
- [Documentation](#documentation)
- [Roadmap](#roadmap)

## Overview

This homelab combines bare-metal servers, virtualization, and container orchestration to create an open source, resilient platform with hybrid cloud integration. It's focused on AMD and Intel GPU solutions for AI/ML workloads.

## Core Infrastructure

**Hardware:**
- **Servers:** 5 servers – ‘Method’ (SuperMicro H12SSL‑i), ‘Indy’ (SuperMicro D‑2146NT), ‘Stale’ (X10SDV‑4C‑TLN4F), ‘Nose’ & ‘Tail’ (Framework Mainboard)
- **Networking:** TP‑Link Omada switches & Protectli Opnsense firewall
- **Accelerated compute:** Intel Arc A310, AMD Radeon AI Pro R9700, AMD Ryzen AI MAX+ 395 “Strix Halo”
- **Management:** UPS, PiKVM

**Software Stack:**
- **Operating Systems**: [Debian](https://www.debian.org/), [Proxmox](https://www.proxmox.com/), [Talos](https://www.talos.dev/), [NixOS](https://nixos.org/), [Truenas](https://www.truenas.com/)
- **Storage:** [Ceph](https://ceph.io/) cluster (hot storage) and [Truenas](https://www.truenas.com/) (cold storage)
- **Container Orchestration:** Ephemeral [Talos](https://www.talos.dev/) [Kubernetes](https://kubernetes.io/) clusters and [Harbor](https://goharbor.io/) proxy/registry
- **Automation:** [OpenTofu](https://opentofu.org/), [Ansible](https://www.ansible.com/), [ArgoCD](https://argo-cd.readthedocs.io/en/stable/), [NixOS](https://nixos.org/), [Argo Events](https://argoproj.github.io/argo-events/) and [Argo Workflows](https://argoproj.github.io/argo-workflows/)
- **Security:** [SOPS](https://github.com/mozilla/sops), [HashiCorp Vault](https://www.vaultproject.io/), [Authelia](https://www.authelia.com/), [Traefik](https://traefik.io/traefik/), VLANs
- **Observability:** [Kube Prometheus Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), [Alloy](https://github.com/grafana/alloy), [LangSmith](https://www.langsmith.com/)

## Key Features

**AI/ML Capabilities:**
- 🤖 Managing device through Intel GPU plugin and AMD ROCm operator
- 🖼️ Immich machine learning & Jellyfin transcoding with Intel Arc A310
- 📦 `llm-models` [Helm chart](kubernetes/charts/llm-models) – scale‑to‑zero [Llama.cpp](https://github.com/ggml-org/llama.cpp) inference via [LiteLLM](https://github.com/BerriAI/litellm)
- 🧠 Embedding model inference with AMD Radeon AI Pro R9700
- ⚡ Dense & MoE inference on AMD Ryzen AI MAX+ 395
- ☁️ GCP Vertex AI for larger ML inference

**Automation:**
- Infrastructure as Code with [OpenTofu](https://opentofu.org/)
- [Debian](https://www.debian.org/), [Proxmox](https://www.proxmox.com/) and [Opnsense](https://opnsense.org/) management with [Ansible](https://www.ansible.com/)
- GitOps deployment with [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
- Blue/green deployment strategies
- Container registry and proxy with Harbor
- [Argo Events](https://argoproj.github.io/argo-events/) and [Argo Workflows](https://argoproj.github.io/argo-workflows/) for backups, secret management and CI/CD pipelines
- [NixOS](https://nixos.org/) for Framework 13 laptop and Aorus gaming desktop
- Common helm chart

**Storage & Backups:**
- [Ceph](https://ceph.io/) backbone
- [SeaweedFS](https://github.com/chrislusf/seaweedfs) PVC hot storage
- [Truenas](https://www.truenas.com/) / [MinIO](https://min.io/) cold storage
- Offsite replication to [Cloudflare R2](https://www.cloudflare.com/products/cloudflare-r2/)
- Automated backups with [Argo Workflows](https://argoproj.github.io/argo-workflows/), [k8up](https://github.com/k8up-io/k8up) and [CloudNative PG](https://cloudnative-pg.io/)

**Security:**
- Network segmentation with OPNsense and intervlan routing with TP Link Omada
- Secrets management with [SOPS](https://github.com/mozilla/sops) and [Vault](https://www.vaultproject.io/)
- Automated TLS certificates with [Cert Manager](https://cert-manager.io/) and [Cloudflare](https://www.cloudflare.com/)
- OIDC/MFA authentication with Authelia
- Middleware and encrypted ingress with Traefik

**Disaster Recovery:**
- Infrastructure-as-Code for rapid rebuilding
- Automated backup restoration workflows and gitops
- Regular disaster recovery testing with blue/green cluster
- 3-2-1 backup strategy

## Documentation

Comprehensive documentation is available in the **[Docker Docs Site](docker/docs-site/docs)** directory, covering architecture, deployments, operations, security, and AI/ML implementations.

## Roadmap
- **Short‑term:** Wireguard VPN & Cloudflare tunnels to publish docs site
- **Mid‑term:** Personal website & publishing project **[lighthearted](https://github.com/blake-hamm/lighthearted)**
- **Long‑term:** Fine‑tuning & building generative models, Home Assistant

*Github issues are more up to date.*
