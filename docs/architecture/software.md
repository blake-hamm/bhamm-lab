# Software Architecture

## Overview

This document outlines the software components and architecture that form the digital backbone of the lab. It details the operating systems, virtualization platforms, container orchestration, storage solutions, automation tools, and configuration management systems that work in unison to deliver a scalable, robust, and automated environment.

## Software Inventory

### Operating Systems & Hypervisors
- **Debian:**
  - **Role:** Primary operating system for bare-metal deployments and virtualization.
  - **Usage:** Ensure simple, secure and stable OS to customize for various use cases.
- **Proxmox:**
  - **Role:** Hypervisor platform for managing virtual machines and containers.
  - **Usage:** Provides virtualization and resource isolation for flexible development environments.
- **NixOS (Decomissioned):** Originally was the preferred Linux OS, but determined to have limited support and ultimately too unstable for my needs.

### Virtualization & Container Orchestration
- **Virtual Machines (VMs):**
  - **Description:** Virtualized instances hosted on Proxmox, used for isolating different workloads and testing environments.
- **K3s/Kubernetes:**
  - **Role:** Container orchestration engine, adopting a container-first approach.
  - **Usage:** Manages containerized applications, core infrastructure services, and microservices deployments.

### Storage & Data Management
- **Ceph:**
  - **Role:** Distributed storage solution.
  - **Usage:** Provides scalable, low latency, redundant storage for VMs, containers, and application data.
- **Snapraid/mergerfs:**
  - **Role:** Redundant storage.
  - **Usage:** Provides secondary file system storage for larger datasets.
- **GCP Storage:**
  - **Role:** Offsite storage.
  - **Usage:** Provide offsite storage to support resiliant backups.

### Automation and Management Tools
- **Terraform:**
  - **Role:** Infrastructure as Code (IaC).
  - **Usage:** Deploy GCP and proxmox resources.
- **Ansible:**
  - **Role:** Configuration management.
  - **Usage:** Configure and install debian, proxmox and opnsense.
- **Argo CD:**
  - **Role:** GitOps continuous deployment tool for Kubernetes environments.
  - **Usage:** Manages and synchronizes Kubernetes deployments directly from Git repositories.
- **Helm:**
  - **Role:** Ensure consistent kubernetes manifests.
  - **Usage:** Leverage common configs like Traefik, External Secrets, PVC, Postgresql databases and backups.
- **Nix:**
  - **Role:** Declarative package management.
  - **Usage:** Ensures consistent development environments.

### Secrets and Configuration Management
- **SOPS:**
  - **Role:** Tools for secure secrets management and encrypted configuration storage.
  - **Usage:** Protect sensitive information such as API keys, credentials, and encryption keys, ensuring that configuration data remains secure.
- **Hashicorp Vault:**
  - **Role:** Tools for secure secrets management and encrypted configuration storage.
  - **Usage:** Protect sensitive information such as API keys, credentials, and encryption keys, ensuring that configuration data remains secure.

### Supporting Software Components
- **Disaster Recovery Tools:**
  - **Examples:** Velero for Kubernetes, restic for backups, and specialized configurations for databases (e.g., PostgreSQL replication).
  - **Usage:** Ensure that critical data and services can be recovered rapidly in the event of failure.
- **Hybrid Cloud Integration:**
  - **Integration with GCP:**
    - **Role:** Augments on-premises capabilities by providing additional backup, AI API access, and compute resources.
    - **Usage:** Supports disaster recovery strategies and offloads compute-intensive tasks when needed.

## Diagrams & Visualizations
- **Architectural Diagrams:**
  - High-level diagrams illustrate the overall software stack, showing how the operating systems, virtualization platforms, and container orchestration interact.
  - Detailed flowcharts map out the integration of automation tools with the infrastructure components.
- **References:**
  *(Include links or embedded images to your architectural diagrams here.)*
