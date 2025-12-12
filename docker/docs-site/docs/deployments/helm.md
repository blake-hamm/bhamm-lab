# Deploying the `common` Helm Chart

The `common` Helm Chart provides a comprehensive set of Kubernetes components for deploying common applications with integrated services. This chart includes:

- **External Secrets:** Integrates with Vault for secure secret management
- **IngressRoutes:** Configures Traefik ingress routes for external access
- **PostgreSQL:** Deploys a CloudNative PG database cluster
- **Backups:** Manages application and database backups with K8up and Argo Workflows
- **Dragonfly:** Optional Redis-compatible in-memory database
- **Persistent Volumes:** Configurable persistent storage for applications


## Prerequisites

- Helm 3 installed
- A running Kubernetes cluster
- Required operators and CRDs:
  - External Secrets operator for Vault integration
  - Traefik operator for ingress management
  - CloudNative PG operator for PostgreSQL
  - K8up operator for application backups
  - Dragonfly operator (if using Redis functionality)
- Access to Ceph, Vault, Traefik, CloudNative PG, and S3 (for backups)


## Chart Configuration

### Basic Chart Information

The chart is located at [`kubernetes/charts/common/`](kubernetes/charts/common/) with version 0.1.0.

### Global Configuration

All components are deployed into a namespace named by the `name` parameter (default: `common-app`).

```yaml
name: common-app  # Base name for all resources
```

### External Secrets Configuration

Configure external secrets for Vault integration:

```yaml
externalSecrets:
  enabled: false                    # Enable external secrets
  labels: {}                        # Additional labels for ExternalSecret
  secrets:
    - name: example-secret          # Secret name
      remoteRef:
        key: secret-key             # Vault secret key
        property: secret-value      # Vault property name
```

### IngressRoutes Configuration

Set up Traefik ingress routes for external access:

```yaml
ingressRoutes:
  - enabled: true
    name: web                      # Route name
    ingressClass: traefik-external # Traefik ingress class
    routes:
      - match: Host(`example.com`)  # Route match condition
        kind: Rule                  # Route kind
        priority: 1                 # Route priority
        services:
          - name: common-app        # Service name
            port: 80                 # Service port
            kind: Service           # Service type (default: Service)
            scheme: https           # Service scheme (default: https)
        # Optional middlewares
        # middlewares:
        #   - name: middleware-name
        #     namespace: traefik
    # Optional websocket support
    # websocket: true
```

### PostgreSQL Configuration

Deploy and configure CloudNative PostgreSQL cluster:

```yaml
postgresql:
  enabled: false                    # Enable PostgreSQL deployment
  instances: 1                      # Number of PostgreSQL instances
  storageSize: 2Gi                  # Storage per instance
  imageName: ""                     # Custom PostgreSQL image (optional)
  databaseName: ""                  # Database name (default: chart name)
  timezone: "America/Denver"        # Database timezone
  sharedPreloadLibraries: [""]      # Shared preload libraries
  postInitSQL: ""                   # Post-initialization SQL

  # Resource limits
  resources:
    requests:
      memory: "200Mi"
      cpu: "250m"
    limits:
      memory: "1000Mi"
      cpu: "1500m"

  # Managed roles
  managed:
    roles: []

  # Backup configuration
  backup:
    enabled: false                  # Enable PostgreSQL backups
    pathVersion: "v1"               # Backup path version
    schedule: "0 30 */12 * * *"     # Cron schedule (every 12 hours)
    retention: "30d"                # Retention period

  # Restore configuration
  restore:
    enabled: false                  # Enable PostgreSQL restore
    pathVersion: "v1"               # Restore path version
    retention: "30d"                # Retention period
```

### K8up Backup Configuration

Set up K8up for application backups:

```yaml
k8up:
  backup:
    enabled: false                  # Enable scheduled backups
    schedule: "0 */12 * * *"        # Cron schedule (every 12 hours)

  restore:
    enabled: false                  # Enable restores
    config:
      fsGroup: 0                    # File system group for restores
```

### Dragonfly Configuration

Optional Redis-compatible in-memory database:

```yaml
dragonfly:
  enabled: false                    # Enable Dragonfly deployment
  replicas: 1                       # Number of replicas
  image: "dragonflydb/dragonfly:latest"  # Docker image
  args: []                          # Additional arguments

  # Resource limits
  resources:
    requests:
      cpu: 500m
      memory: 500Mi
    limits:
      cpu: 600m
      memory: 750Mi

  # Snapshot configuration
  snapshot:
    enabled: false                  # Enable snapshots
    cron: "*/5 * * * *"             # Snapshot schedule
    pvc:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 2Gi              # Snapshot storage size
```

### Persistent Volume Configuration

Configure persistent volumes for applications:

```yaml
pvc:
  - name: my-pvc-1                  # PVC name
    storageSize: 10Gi               # Storage size
    storageClassName: local-path    # Storage class
    accessMode: ReadWriteOnce       # Access mode
```

## Installation

### Install with Default Values

```bash
helm install common ./kubernetes/charts/common/
```

### Install with Custom Values

```bash
helm install common ./kubernetes/charts/common/ \
  --set externalSecrets.enabled=true \
  --set postgresql.enabled=true \
  --set postgresql.instances=3 \
  --set k8up.backup.enabled=true
```

### Upgrade Release

```bash
helm upgrade common ./kubernetes/charts/common/ \
  --values custom-values.yaml
```

## Template Files

The chart includes the following template files:

- [`external-secret.yaml`](kubernetes/charts/common/templates/external-secret.yaml:1) - ExternalSecret configuration
- [`ingress-route.yaml`](kubernetes/charts/common/templates/ingress-route.yaml:1) - Traefik IngressRoute configuration
- [`pg-cluster.yaml`](kubernetes/charts/common/templates/pg-cluster.yaml:1) - PostgreSQL cluster configuration
- [`pg-backup.yaml`](kubernetes/charts/common/templates/pg-backup.yaml:1) - PostgreSQL backup configuration
- [`k8up-schedule.yaml`](kubernetes/charts/common/templates/k8up-schedule.yaml:1) - K8up backup schedule
- [`dragonfly.yaml`](kubernetes/charts/common/templates/dragonfly.yaml:1) - Dragonfly database configuration
- [`pvc.yaml`](kubernetes/charts/common/templates/pvc.yaml:1) - Persistent volume configuration
- Additional templates for RBAC, external secrets, and restore operations

## Values Reference

For a complete list of configuration options, see [`values.yaml`](kubernetes/charts/common/values.yaml:1).
