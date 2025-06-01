
# Overview

- **Purpose**: Rapid restoration of critical data and infrastructure using Infrastructure-as-Code (IaC) with minimal manual intervention
- **Core Principle**: Treat servers and clusters as cattle, not pets - rebuild via automation
- **Scope**:
  - Critical Data: Kubernetes PVCs and CloudNative-PG databases
  - IaC-Managed Infrastructure: Proxmox, OPNsense, Talos VMs, Kubernetes apps

## Backup Architecture
```mermaid
graph LR
A[K8s PVCs] -->|k8up daily| B[Minio/NFS]
C[CloudNative-PG DBs] -->|Native daily| D[Minio/NFS]
B -->|Bi-monthly| E[GCP Storage]
D -->|Bi-monthly| E[GCP Storage]
```

## Backup Components
| Component         | Tool/Method       | Frequency | Location         | Retention |
|-------------------|-------------------|-----------|------------------|-----------|
| Kubernetes PVCs   | k8up              | Daily     | Minio/NFS        | 30 days   |
| PostgreSQL DBs    | CloudNative-PG    | Daily     | Minio/NFS (separate bucket) | 30 days |
| Minio Bucket Data | PVC Backup        | 2x/month  | GCP Storage      | 6 months  |

## Restoration Workflow
1. **Infrastructure Recovery**:
    - Proxmox: Install Debian and rebuild via Ansible playbooks
    - OPNsense: Install latest, configure auth and reconfigure via Ansible
    - Kubernetes: Redeploy via Terraform + ArgoCD (GitOps)

2. **Data Recovery**:
```mermaid
sequenceDiagram
    participant GCP as GCP Storage
    participant Minio as Minio/NFS
    participant K8s as Kubernetes
    GCP->>Minio: Restore PVC backups (if Minio unavailable)
    Minio->>K8s: k8up restore PVCs
    Minio->>Postgres: CloudNative-PG restore
```

## Future Enhancements

1. **Enhanced Recovery Reliability**:
    - Clarify minio nfs recovery procedure and test with blue cluster
    - Added explicit retention policies to GCP Storage
    - Define RTO and building testing environment

2. **Automation Focus**:
    - Removed manual failover procedures
    - Deprecated hardware-specific recovery steps

3. **Hybrid Cloud High Availability**:
    - Enable failover to GCP if cable internet goes down

## Related Documents
- [Cloudnative PG](cloudnative_pg.md): PostgreSQL backup/restore details
- [Kubernetes PVC](kubernetes.md): k8up configuration and procedure
