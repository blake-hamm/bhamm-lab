# Software

## Overview

This document outlines the software components that form the digital backbone of the lab. It details the operating systems, virtualization platforms, container orchestration, storage solutions, automation tools, and configuration management systems that work in unison to deliver a scalable, robust, and automated environment.

## Software Inventory

### Operating Systems & Hypervisors

- **Debian:**
  - *Role:* Primary operating system for bare-metal deployments.
  - *Usage:* Ensure simple, secure and stable OS to customize for various use cases.
- **Proxmox:**
  - *Role:* Hypervisor platform for managing virtual machines and containers.
  - *Usage:* Provides virtualization and resource isolation for flexible development environments (generally prefer to install with Ansible `lae.proxmox` on a Debian machine for finer control).
- **Talos:**
  - *Role:* Primary operating system for kubernetes.
  - *Usage:* Operating system running my blue/green kubernetes clusters. Ensures immutable, API-managed, and stripped of non-Kubernetes component. Also, simpler deployment with Terraform.
- **NixOS:**
  - *Role:* Primary operating system for personal framework 13 laptop.
  - *Usage:* Reproducable, declarative customization (ricing).

### Virtualization & Container Orchestration

- **Virtual Machines (VMs):**
  - *Role:* Isolated compute instances for diverse workloads.
  - *Platform:* Proxmox VE.
  - *Usage:* Sandbox development environments, legacy applications, and security-critical services requiring full OS isolation.

- **Kubernetes (Talos):**
  - *Role:* Primary container orchestration platform.
  - *Platform:* Talos Linux (see [Operating Systems](#operating-systems--hypervisors)).
  - *Usage:* Manages all containerized microservices, stateful applications, and cluster networking via Cilium CNI.
  - *Deployment:* Fully defined in Terraform for immutable infrastructure.

- **Harbor:**
  - *Role:* Store docker containers and helm charts.
  - *Usage:*
    - Any changes or new directories in the `docker` will automatically build a container
    - Dockerhub proxy to cache images locally

- **K3s [DEPRECATED]:**
  - *Role:* Previous lightweight Kubernetes distribution.
  - *Platform:* Debian VMs/bare-metal (systemd service).
  - *Note:* Replaced due to Cilium compatibility issues and operational complexity from mixed Terraform/Ansible tooling.

### Storage & Data Management
*Multi-tiered storage strategy balancing performance, redundancy, and cost efficiency.*

- **Ceph:**
  - *Role:* Primary distributed storage cluster
  - *Usage:* Low-latency, highly available block storage for kubernetes
  - *Workloads:* Live application data, ephemeral volumes, and hot-tier object storage

- **ZFS:**
  - *Role:* High-performance local storage
  - *Usage:* ZFS mirrors on each Proxmox host for VM root disks (faster boot/operations)
  - *Config:* LZ4 compression, frequent snapshots

- **Snapraid + mergerfs:**
  - *Role:* Cost-effective bulk storage
  - *Usage:* Secondary storage for large datasets (media/archives) with NFS export
  - *Redundancy:* Snapraid parity protection on Aorus server

- **Minio [Transitioning to Garage]:**
  - *Role:* S3-compatible object storage
  - *Backends:*
    - **Ceph-backed:** Argo artifacts, Harbor images, Forgejo, Loki, Terraform state
    - **NFS-backed:** k8up and CloudNative PG backups
  - *Migration Reason:* Garage offers better resource efficiency and multi-node support

- **GCP Cloud Storage:**
  - *Role:* Offsite backup tier
  - *Usage:* Encrypted backups of NFS-based Minio bucket (k8up/CNPG backups only)
  - *Retention:* Immutable 90-day snapshots

### Automation and Management Tools
*End-to-end automation from infrastructure provisioning to application deployment.*

- **Terraform:**
  - *Role:* Infrastructure as Code (IaC) foundation
  - *Usage:* Provision and manage GCP resources, Proxmox VMs, and Talos Kubernetes clusters

- **Ansible:**
  - *Role:* Configuration management and OS orchestration
  - *Usage:*
    - Debian: Base system hardening and package management
    - Proxmox: Hypervisor deployment on bare-metal
    - OPNsense: Network appliance configuration

- **Argo CD:**
  - *Role:* GitOps engine for Kubernetes
  - *Usage:* Continuous synchronization of Helm releases and raw manifests from Git repos
  - *Coverage:* Manages 100% of cluster applications (including itself via App-of-Apps)

- **Helm:**
  - *Role:* Kubernetes package and release manager
  - *Usage:* Standardized templating for:
    - Infrastructure: Traefik, Cilium CNI, External Secrets
    - Data Services: PostgreSQL (CloudNativePG), backup operators (k8up)
    - Storage: CSI drivers and PVC configurations

- **Nix:**
  - *Role:* Declarative development environment manager
  - *Usage:* Reproducible toolchains and dependencies via `shell.nix`/`flake.nix`
  - *Integration:* Complements NixOS for non-OS environments

### Security and Secrets
*Multi-layered approach combining static encryption and dynamic secrets orchestration.*

- **SOPS (Secrets OPerationS):**
  - *Role:* Encrypted secrets storage for version-controlled files
  - *Usage:*
    - Encrypting Kubernetes manifests, Terraform variables, and Ansible vaults
    - Git-friendly encryption of API keys, credentials, and TLS certificates
    - Key management via GCP KMS
  - *Workflow:* Changes in decrypted file in git triggers sync to Hashicorp Vault with Argo workflow

- **Hashicorp Vault:**
  - *Role:* Secrets engine
  - *Usage:* Secure storage of root secrets accessible accross apps and cluster
  - *Integration:* Primarily accessed via External Secrets Operator in Kubernetes, but also available in Argo workflows in CI/CD

- **Authelia:**
  - *Role:* Unified authentication gateway (OIDC provider)
  - *Usage:*
    - Single Sign-On (SSO) for Argo CD, Forgejo, and Proxmox
    - Two-factor authentication (2FA) enforcement
    - Policy-based access controls (RBAC) for web applications
  - *Integration:*
    - Traefik middleware for authentication forwarding

- **Cert Manager + Cloudflare:**
  - *Role:* Automated TLS certificate authority
  - *Usage:*
    - Issuing trusted wildcard certificates (`*.your-domain.com`)
    - Automated renewal via DNS-01 challenges
    - Certificate injection for Traefik ingress routes

- **Traefik:**
  - *Role:* Secure ingress proxy
  - *Security Implementations:*
    - TLS termination with automatic cert rotation
    - Rate limiting for DDoS protection
    - IP allowlisting for admin interfaces
    - HTTP → HTTPS redirect enforcement
    - Security headers (CSP, XSS protection)

### Networking

- **OPNsense:**
  - *Role:* Primary firewall/router
  - *Usage:* VLAN segmentation, WireGuard VPN, and DoH/DoT filtering
- **Cilium:**
  - *Role:* Kubernetes CNI + Service Mesh
  - *Usage:* L7 network policies, Hubble observability, and encrypted pod traffic
- **CoreDNS:**
  - *Role:* Cluster DNS resolver
  - *Usage:* Internal service discovery with split-horizon DNS


### Monitoring

- **Prometheus/Grafana:**
  - *Role:* Metrics collection and visualization
  - *Coverage:* Node/VM metrics, Ceph cluster, Kubernetes resources
- **Loki:**
  - *Role:* Log aggregation
  - *Sources:* Proxmox, Talos, Opnsense and application logs via Promtail
- **Alertmanager:**
  - *Role:* Incident routing
  - *Triggers:* Ceph OSD down, storage >90% full, pod crash loops

### Backups and Disaster Recovery
- **k8up + CloudNative PG:**
  - *Role:* Kubernetes application backups
  - *Target:* Minio → GCP (encrypted via Vault)

### Dev tools
- **Forgejo:**
  - *Role:* Self-hosted Git
  - *Integration:* Webhook triggers Argo events/workflows for CI
- **Argo CD/Events/Workflows:**
  - *Role:* CI pipelines
  - *Usage:* Build/test container images on push
- **Renovate [not yet implemented]:**
  - *Role:* Dependency updates
  - *Coverage:* Helm charts, container images, Terraform modules
