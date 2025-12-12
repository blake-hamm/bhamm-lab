
# Overview

- **Purpose**: Rapid restoration of critical data and infrastructure using Infrastructure-as-Code (IaC) with minimal manual intervention
- **Core Principle**: Treat servers and clusters as cattle, not pets - rebuild via automation
- **Scope**:
  - Critical Data: Kubernetes PVCs and CloudNative-PG databases
  - IaC-Managed Infrastructure: Proxmox, OPNsense, Talos VMs, Kubernetes apps

## Backup Architecture
```mermaid
graph LR
A[k3s PVCs] -->|Every 6 hours| C[SeaweedFS]
B[CloudNative-PG DBs] -->|Every 6 hours| C[SeaweedFS]
C -->|Daily| D[Minio on TrueNAS VM]
D -->|Daily| E[Cloudflare R2]
```

## Backup Components
| Component         | Tool/Method       | Frequency | Location         |
|-------------------|-------------------|-----------|------------------|
| Kubernetes PVCs   | k8up              | 3 hrs     | Minio/NFS        |
| PostgreSQL DBs    | CloudNative-PG    | 3 hrs     | Minio/NFS (separate bucket) |
| Minio Bucket Data | PVC Backup        | Daily     | GCP Storage      |

## Restoration Workflow
1. **Infrastructure Recovery**:
    - Proxmox: Install Debian and rebuild via Ansible playbooks
    - OPNsense: Install latest, configure auth and reconfigure via Ansible
    - Kubernetes: Redeploy via Terraform + ArgoCD (GitOps)

2. **Data Recovery**:
```mermaid
sequenceDiagram
    participant r2 as Cloudflare R2 (Mirror)
    participant minio as Minio (TrueNAS VM)
    participant swfs as SeaweedFS
    participant pvc as PVCs
    participant cnpg as CNPG Databases

    minio->>swfs: Restore SeaweedFS
    r2->>swfs: Alternative restore from R2
    Note over swfs: SeaweedFS is restored
    swfs->>pvc: Restore PVCs
    swfs->>cnpg: Restore CNPG Databases
```

## Future Enhancements

- **Hybrid Cloud High Availability**:
    - Enable failover to GCP if cable internet goes down

## Related Documents
- [Cloudnative PG](cloudnative_pg.md): PostgreSQL backup/restore details
- [Kubernetes PVC](kubernetes.md): k8up configuration and procedure
