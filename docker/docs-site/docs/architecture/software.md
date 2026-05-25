# Software

## Overview

This document outlines the software components that form the digital backbone of
the lab. It details the operating systems, virtualization platforms, container
orchestration, storage solutions, automation tools, and configuration management
systems that work in unison to deliver a scalable, robust, and automated
environment.

## Software Inventory

### Operating Systems & Hypervisors

- **Debian:**
  - _Role:_ Primary operating system for bare-metal deployments.
  - _Usage:_ Ensure simple, secure and stable OS to customize for various use
    cases.
- **Proxmox:**
  - _Role:_ Hypervisor platform for managing virtual machines and containers.
  - _Usage:_ Provides virtualization and resource isolation for flexible
    development environments (generally prefer to install with Ansible
    `lae.proxmox` on a Debian machine for finer control).
- **Talos:**
  - _Role:_ Primary operating system for kubernetes.
  - _Usage:_ Operating system running my blue/green kubernetes clusters. Ensures
    immutable, API-managed, and stripped of non-Kubernetes component. Also,
    simpler deployment with Terraform.
- **NixOS:**
  - _Role:_ Declarative OS for personal machines, VMs, and SBCs.
  - _Usage:_ Reproducible, declarative configuration across:
    - **Framework 13 laptop:** Desktop environment with NixOS modules for dev,
      AI, and backups.
    - **Garage VM:** Object storage server on Proxmox `japan` with HBA PCIe
      passthrough.
    - **Orange Pi Zero3 (x2):** Pi-hole DNS servers and NUT UPS monitoring on
      aarch64/ARM SBCs.

### Virtualization & Container Orchestration

- **Virtual Machines (VMs):**
  - _Role:_ Isolated compute instances for diverse workloads.
  - _Platform:_ Proxmox VE.
  - _Usage:_ Sandbox development environments, legacy applications, and
    security-critical services requiring full OS isolation.

- **Kubernetes (Talos):**
  - _Role:_ Primary container orchestration platform.
  - _Platform:_ Talos Linux (see
    [Operating Systems](#operating-systems--hypervisors)).
  - _Usage:_ Manages all containerized microservices, stateful applications, and
    cluster networking via Cilium CNI.
  - _Deployment:_ Fully defined in Terraform for immutable infrastructure.

- **Harbor:**
  - _Role:_ Store docker containers and helm charts.
  - _Usage:_
    - Any changes or new directories in the `docker` will automatically build a
      container
    - Dockerhub proxy to cache images locally

- **K3s [DEPRECATED]:**
  - _Role:_ Previous lightweight Kubernetes distribution.
  - _Platform:_ Debian VMs/bare-metal (systemd service).
  - _Note:_ Replaced due to Cilium compatibility issues and operational
    complexity from mixed Terraform/Ansible tooling.

### Storage & Data Management

_Multi-tiered storage strategy balancing performance, redundancy, and cost
efficiency._

- **Local LVM:**
  - _Role:_ Boot and primary VM storage for Proxmox
  - _Usage:_ Managed by the Ansible `storage` role. Uses a consistent `local-vg`
    volume group name across all Proxmox hosts so Terraform and the
    `lae.proxmox` role can provision VMs without per-host logic.
  - _Modes:_
    - **Dedicated VM drive:** All Proxmox hosts use a dedicated boot drive and a
      separate VM storage device. The boot drive keeps its original VG name
      (`<hostname>-vg`) with root at 100GB and swap at 4GB; a second `local-vg`
      is created on the dedicated VM storage device.
    - **Legacy single-drive:** Root VG (`<hostname>-vg`) is renamed to
      `local-vg` on hosts with one disk. Root LV is capped at 100GB, swap at
      4GB; remaining space hosts VMs. (No longer used.)

- **Ceph:**
  - _Role:_ Primary distributed storage cluster
  - _Usage:_ Low-latency, highly available block storage for kubernetes
  - _Workloads:_ Live application data, ephemeral volumes, and hot-tier object
    storage

- **Ceph RGW (RADOS Gateway):**
  - _Role:_ Primary S3-compatible object storage
  - _Backend:_ Ceph, runs directly on Proxmox nodes via Ansible
  - _Usage:_ S3 endpoint for all cluster workloads
  - _Workloads:_ Argo workflow artifacts, k8up PVC backups, CloudNative PG
    backups/WAL, tofu state, Loki log data, Proxmox Backup Server data
  - _Buckets:_ `tofu-state`, `loki-data`, `argo-artifacts`, `cnpg-backups`,
    `k8up-backups`, `beyond-vibes`, `mlflow`, `proxmox-backup-server`
  - _Endpoint:_ `rgw.bhamm-lab.com`

- **Garage:**
  - _Role:_ Local S3-compatible backup mirror
  - _Platform:_ NixOS VM on Proxmox `japan` (`10.0.20.21`, `10.0.30.21`)
  - _Storage:_ 3x physical SSDs via HBA PCIe passthrough (2x PNY 2TB, 1x Crucial
    1TB)
  - _Usage:_ Daily rclone mirror of all Ceph RGW buckets. Intermediate tier for
    offsite replication.
  - _Replaces:_ TrueNAS/MinIO as local backup target

- **Backblaze B2:**
  - _Role:_ Primary offsite backup tier
  - _Usage:_ Weekly rclone sync from Garage. Provides 3-2-1 backup compliance.
  - _Integration:_ Synced via Argo CronWorkflow (`ceph-rgw-backup`) running
    weekly

- **Cloudflare R2:**
  - _Role:_ Secondary/standby offsite backup tier
  - _Usage:_ Standby fallback for disaster recovery. Restore path: R2 → Garage →
    Ceph RGW.
  - _Note:_ No longer primary offsite — replaced by cheaper Backblaze B2

- **ZFS [DEPRECATED]:**
  - _Role:_ High-performance local storage
  - _Usage:_ ZFS mirrors on each Proxmox host for VM root disks (faster
    boot/operations)
  - _Config:_ LZ4 compression, frequent snapshots

- **Snapraid + mergerfs [DEPRECATED]:**
  - _Role:_ Cost-effective bulk storage
  - _Usage:_ Secondary storage for large datasets (media/archives) with NFS
    export
  - _Redundancy:_ Snapraid parity protection on Aorus server

- **GCP Cloud Storage [DEPRECATED]:**
  - _Role:_ Former offsite backup tier (replaced by Backblaze B2)
  - _Usage:_ Previously used for encrypted backups of Minio bucket. Replaced by
    Backblaze B2 for cost efficiency and simpler integration.
  - _Retention:_ Used immutable 90-day snapshots

- **SeaweedFS [DEPRECATED]:**
  - _Role:_ Former in-cluster S3 storage solution (replaced by Ceph RGW)
  - _Usage:_ Previously ran as a pod in Kubernetes backed by Ceph RBD. Migrated
    to Ceph RGW for block-level performance benefits, fewer moving parts, and
    direct integration with Proxmox Ceph.
  - _Workloads:_ Previously handled k8up backups, CNPG WAL, argo artifacts, tofu
    state, Loki data. These now target Ceph RGW directly.

- **TrueNAS [DEPRECATED]:**
  - _Role:_ Former local backup target (replaced by Garage)
  - _Usage:_ Previously hosted MinIO VM and provided NFS storage for SeaweedFS
    backups. Replaced by Garage running on NixOS — better control, declarative
    config, and native NixOS support.

- **MinIO [DEPRECATED]:**
  - _Role:_ Former S3 gateway on TrueNAS (replaced by Garage)
  - _Usage:_ Previously exposed TrueNAS storage via S3 for backup workflows.
    Garage provides the same S3-compatible interface with full NixOS-native
    deployment and no dependency on TrueNAS.

### Automation and Management Tools

_End-to-end automation from infrastructure provisioning to application
deployment._

- **Terraform:**
  - _Role:_ Infrastructure as Code (IaC) foundation
  - _Usage:_ Provision and manage GCP resources, Proxmox VMs, and Talos
    Kubernetes clusters

- **Ansible:**
  - _Role:_ Configuration management and OS orchestration
  - _Usage:_
    - Debian: Base system hardening and package management
    - Proxmox: Hypervisor deployment on bare-metal
    - OPNsense: Network appliance configuration

- **Argo CD:**
  - _Role:_ GitOps engine for Kubernetes
  - _Usage:_ Continuous synchronization of Helm releases and raw manifests from
    Git repos
  - _Coverage:_ Manages 100% of cluster applications (including itself via
    App-of-Apps)

- **Helm:**
  - _Role:_ Kubernetes package and release manager
  - _Usage:_ Standardized templating for:
    - Infrastructure: Traefik, Cilium CNI, External Secrets
    - Data Services: PostgreSQL (CloudNativePG), backup operators (k8up)
    - Storage: CSI drivers and PVC configurations

- **Nix:**
  - _Role:_ Declarative development environment manager
  - _Usage:_ Reproducible toolchains and dependencies via
    `shell.nix`/`flake.nix`
  - _Integration:_ Complements NixOS for non-OS environments

### Security and Secrets

_Multi-layered approach combining static encryption and dynamic secrets
orchestration._

- **SOPS (Secrets OPerationS):**
  - _Role:_ Encrypted secrets storage for version-controlled files
  - _Usage:_
    - Encrypting Kubernetes manifests, Terraform variables, and Ansible vaults
    - Git-friendly encryption of API keys, credentials, and TLS certificates
    - Key management via GCP KMS
  - _Workflow:_ Changes in decrypted file in git triggers sync to Hashicorp
    Vault with Argo workflow

- **Hashicorp Vault:**
  - _Role:_ Secrets engine
  - _Usage:_ Secure storage of root secrets accessible accross apps and cluster
  - _Integration:_ Primarily accessed via External Secrets Operator in
    Kubernetes, but also available in Argo workflows in CI/CD

- **Authelia:**
  - _Role:_ Unified authentication gateway (OIDC provider)
  - _Usage:_
    - Single Sign-On (SSO) for Argo CD, Forgejo, and Proxmox
    - Two-factor authentication (2FA) enforcement
    - Policy-based access controls (RBAC) for web applications
  - _Integration:_
    - Traefik middleware for authentication forwarding

- **Cert Manager + Cloudflare:**
  - _Role:_ Automated TLS certificate authority
  - _Usage:_
    - Issuing trusted wildcard certificates (`*.your-domain.com`)
    - Automated renewal via DNS-01 challenges
    - Certificate injection for Traefik ingress routes

- **Traefik:**
  - _Role:_ Secure ingress proxy
  - _Security Implementations:_
    - TLS termination with automatic cert rotation
    - Rate limiting for DDoS protection
    - IP allowlisting for admin interfaces
    - HTTP → HTTPS redirect enforcement
    - Security headers (CSP, XSS protection)

### Networking

- **OPNsense:**
  - _Role:_ Primary firewall/router
  - _Usage:_ VLAN segmentation, WireGuard VPN, and DoH/DoT filtering
- **Pi-hole:**
  - _Role:_ Primary DNS server for main VLANs, Proxmox hosts, and Talos
    Kubernetes nodes
  - _Platform:_ Orange Pi Zero3 (aarch64/ARM) running NixOS
  - _VIP:_ 10.0.9.2 (gateway: 10.0.9.1 OPNsense)
  - _Primary:_ 10.0.9.3 — Orange Pi Zero3 (VRRP MASTER)
  - _Backup:_ 10.0.9.4 — Orange Pi Zero3 Backup (VRRP BACKUP)
  - _Usage:_ Network-wide DNS ad-blocking and filtering with automatic failover
    via Keepalived (VRRP)
  - _Components:_ Pi-hole FTL (DNS filtering) and Pi-hole Web (admin interface
    on ports 80/443)
  - _Deployment:_ Managed via Colmena from `nix/hosts/orangepi-zero3/` and
    `nix/hosts/orangepi-zero3-backup/`
  - _Failover:_ < 3 second switchover when primary Pi-hole or host fails

- **NUT (Network UPS Tools):**
  - _Role:_ UPS monitoring and graceful shutdown across the lab
  - _Primary Servers:_ Orange Pi Zero3 devices running NixOS (`10.0.9.3` and
    `10.0.9.4`)
    - _Usage:_ Each Orange Pi runs an independent NUT server (`upsd`) monitoring
      its attached CyberPower UPS via `usbhid-ups`
    - _Components:_ `usbhid-ups` driver, `upsd` server, `upsmon` primary monitor
    - _Deployment:_ Shared config via `nix/profiles/orangepi-pihole.nix`,
      managed via Colmena
    - _FSD Threshold:_ Global Forced Shutdown is triggered when battery reaches
      20%
  - _Proxmox Clients:_ `method`, `indy`, `japan`
    - _Usage:_ NUT secondary clients monitoring `cyberpower@10.0.9.3` with a
      10-minute `upssched` timer. If power is restored within 10 minutes,
      shutdown is cancelled; otherwise the node shuts down gracefully before
      FSD.
    - _Deployment:_ Managed via Ansible `proxmox` role
  - _Talos Clients:_ `nose`, `tail` (bare-metal Framework nodes)
    - _Usage:_ NUT secondary clients using the `siderolabs/nut-client` Talos
      system extension to monitor `cyberpower@10.0.9.4`
    - _Shutdown:_ Responds to FSD only (`SHUTDOWNCMD "/sbin/poweroff"`)
    - _Deployment:_ Extension baked into the AMD Framework schematic;
      configuration applied via OpenTofu `ExtensionServiceConfig` patch
- **Cilium:**
  - _Role:_ Kubernetes CNI + Service Mesh
  - _Usage:_ L7 network policies, Hubble observability, and encrypted pod
    traffic
- **CoreDNS:**
  - _Role:_ Cluster DNS resolver
  - _Usage:_ Internal service discovery with split-horizon DNS
- **Cloudflare Tunnels:**
  - _Role:_ Secure service exposure to the public internet
  - _Usage:_ Exposes a curated set of Kubernetes services to the public internet
    via Cloudflare's edge network
  - _Security Benefits:_
    - End-to-end encryption via Cloudflare's edge network
    - No public IP exposure on Kubernetes services
    - WAF and DDoS protection at the edge
    - IP allowlisting and rate limiting capabilities
  - _Integration:_ Works with Cloudflare DNS and leverages kubernetes operator
    to deploy services

### Monitoring

- **Prometheus/Grafana:**
  - _Role:_ Metrics collection and visualization
  - _Coverage:_ Node/VM metrics, Ceph cluster, Kubernetes resources
- **Loki:**
  - _Role:_ Log aggregation
  - _Sources:_ Proxmox, Talos, Opnsense and application logs via Promtail
- **Alertmanager:**
  - _Role:_ Incident routing
  - _Triggers:_ Ceph OSD down, storage >90% full, pod crash loops

### Backups and Disaster Recovery

- **k8up + CloudNative PG:**
  - _Role:_ Kubernetes application backups
  - _Workflow:_ PVCs and databases are backed up directly to Ceph RGW (S3). An
    Argo CronWorkflow mirrors Ceph RGW → Garage (local mirror, weekly) →
    Backblaze B2 (offsite, weekly). Cloudflare R2 serves as a standby restore
    source.
  - _Restore Process:_ Argo workflow syncs data from Garage (or R2 as fallback)
    back to Ceph RGW, then k8up/CNPG restore PVCs and databases from RGW.

### Dev Tools

- **Forgejo:**
  - _Role:_ Self-hosted Git
  - _Integration:_ Webhook triggers Argo events/workflows for CI
- **Argo CD/Events/Workflows:**
  - _Role:_ CI pipelines and backup/restore orchestration
  - _Usage:_ Build/test container images on push
- **Renovate [not yet implemented]:**
  - _Role:_ Dependency updates
  - _Coverage:_ Helm charts, container images, Terraform modules
