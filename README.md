# bhamm-lab

A comprehensive self-hosted homelab environment designed for AI/ML workloads, DevOps experimentation and security research.

## Overview

This homelab combines bare-metal servers, virtualization, and container orchestration to create an open source, resilient platform with hybrid cloud integration. It's focused on AMD and Intel GPU solutions for AI/ML workloads.

## Core Infrastructure

**Hardware:**
- 5 servers: 'Method' (SuperMicro H12SSL-i), 'Indy' (SuperMicro D-2146NT), 'Stale' (X10SDV-4C-TLN4F), 'Nose' and 'Tail' (both Framework Mainboard)
- Networking with TP-Link Omada switches and Protectli Opnsense firewall
- Accelerated compute (Intel Arc A310, AMD Radeon AI Pro R9700, AMD Ryzen AI MAX+ 395 "Strix Halo")
- UPS
- PiKVM for management

**Software Stack:**
- **Hypervisors:** Proxmox (VMs)
- **Operating Systems**: Debian, Proxmox, Talos, NixOS, Truenas
- **Storage:** Ceph cluster (hot storage) and Truenas (cold storage)
- **Container Orchestration:** Ephemeral talos kubernetes clusters and Harbor proxy/registry
- **Automation:** OpenTofu, Ansible, ArgoCD (GitOps), NixOS, Argo events and workflows
- **Security:** SOPS, HashiCorp Vault, Authelia, Traefik, VLANs
- **Observability:** Kube prometheus stack, Alloy and LangSmith

## Key Features

**AI/ML Capabilities:**
- Managing device through Intel GPU plugin and AMD ROCm operator
- Immich machine learning and jellyfin transcoding with Intel Arc A310
- llm-models helm chart to enable scale to zero for llama.cpp inference exposed through LiteLLM
- Embedding model inference with AMD Radeon AI Pro R9700
- Dense and MoE inference on AMD Ryzen AI MAX+ 395
- GCP Vertex AI for larger ML inference

**Automation:**
- Infrastructure as Code with OpenTofu
- Debian, Proxmox and Opnsense management with Ansible
- GitOps deployment with ArgoCD
- Blue/green deployment strategies
- Container registry and proxy with Harbor
- Argo event and workflows for backups, secret management and CI/CD pipelines
- NixOS for Framework 13 laptop and Aorus gaming desktop
- Common helm chart

**Storage & Backups:**
- Ceph backbone
- Seaweedfs/pvc hot storage
- Truenas/minio cold storage
- Offsite replication to Cloudflare R2
- Automated backups with argo workflows, k8up and CloudNative PG

**Security:**
- Network segmentation with OPNsense and intervlan routing with TP Link Omada
- Secrets management with SOPS and Vault
- Automated TLS certificates with Cert Manager and Cloudflare
- OIDC/MFA authentication with Authelia
- Middleware and encrypted ingress with Traefik

**Disaster Recovery:**
- Infrastructure-as-Code for rapid rebuilding
- Automated backup restoration workflows and gitops
- Regular disaster recovery testing with blue/green cluster
- 3-2-1 backup strategy

## Documentation

Comprehensive documentation is available in the [`docker/docs-site/docs`](docker/docs-site/docs) directory, covering architecture, deployments, operations, security, and AI/ML implementations.

## Roadmap

*Github issues are more up to date.*

- **Short-term:** Wireguard VPN and Cloudflare tunnels to publish docs site
- **Mid-term:** Personal Website and publishing project [lighthearted](https://github.com/blake-hamm/lighthearted)
- **Long-term:** Fine tuning and building generative models, Home Assistant
