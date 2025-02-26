# Deploying the `common` Helm Chart

This chart integrates key components into your Kubernetes cluster:
- **External Secrets:** Integrates with Vault.
- **IngressRoutes:** Configures Traefik ingress routes.
- **PostgreSQL:** Deploys a CloudNative PG database.
- **Backups:** Manages backups with K8up and Argo Workflow.


## Prerequisites
- Helm 3 installed.
- A running Kubernetes cluster.
- Operators/CRDS and access for Ceph, Vault, Traefik, CloudNative PG, and S3 (for backups).


## Key Configurations

### External Secrets
Configure external secrets as follows:
```yaml
    externalSecrets:
      enabled: true             # Enable external secrets
      secrets:
        - name: my-secret
          remoteRef:
            key: my-vault-key
            property: my-secret-property
```

### IngressRoutes
Set up ingress routes with:
```yaml
    ingressRoutes:
      - enabled: true
        name: web
        ingressClass: traefik-external
        routes:
          - match: Host(`example.com`)
            kind: Rule
            services:
              - name: common-app
                port: 80
```

### PostgreSQL & Backups
Deploy PostgreSQL and configure its backups:
```yaml
    postgresql:
      enabled: true             # Enable PostgreSQL deployment
      instances: 2              # Number of instances
      storageSize: 5Gi          # Storage per instance
      backups:
        enabled: true           # Enable PostgreSQL backups
        schedule: "0 0 * * *"   # Cron schedule for backups
        retention: 30           # Number of backups to retain
        s3Path: "s3://your-bucket/postgres-backups"
        s3Secret: "minio-creds"
```

### K8up Backup & Restore
Set up K8up for backups (and optional restores):
```yaml
    k8up:
      backup:
        enabled: true           # Enable scheduled backups
        schedule: "0 8 * * *"   # Cron schedule (8 AM UTC / 1 AM MST)
      restore:
        enabled: false          # Enable restores if needed
        snapshot: ""
```

## Troubleshooting

