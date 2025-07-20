# ArgoCD

## Base apps
-wave -1 Monitor
-wave -1 ArgoCD
-wave 0 Ceph (csi)
-wave 0 NFS (csi)
-wave 0 Rancher local path provisioner
-wave 0 Operators/crds
  - k8up
  - Cert manager
  - Kubernetes metrics
  - Vault
  - Traefik
-wave 0 seaweedfs ns
-wave 1 cert manager smon for metrics
-wave 1 k8up helm
-wave 1 Checkpoint job for storage health
-wave 1 Seaweedfs deployment
-wave 1 Cilum config
-wave 2 Vault
-wave 2 CloudnativePG
-wave 2 Checkpoint job for seaweedfs s3 health
-wave 3 Checkpoint job for vault health
-wave 3 External Secrets
-wave 3 argo events helm
-wave 3 Seaweedfs k8up offsite restore from gcp
-wave 4 Vault secret store
-wave 4 argo eventbus
-wave 5 push seaweedfs s3 credentails to vault
-wave 6 argo workflows helm
-wave 7 Vault secret sync argo workflow
-wave 7 Automation app
-wave 8 argo workflow - rclone s3 create buckets (k8up/cnpg)
-wave 8 nfs common (secrets for k8up restore/backup)
-wave 9 Test ns
-wave 10 Test common (k8up/cnpg backups)
-wave 10 Test pvc
-wave 11 Test dp
-wave 12 Test CronWorkflow (timestamp on index.html in pvc)
-wave 12 Test svc
-wave 18 Test CronWorkflow (timestamp on cnpg)
-wave 15 Cert manager common
-wave 15 Authelia Common
-wave 15 Traefik Middleware
-wave 16 Authelia Helm
-wave 16 STAGE: Cert manager cluster issuer
-wave 17 STAGE: Certificate in traefik ns
-wave 18 PROD: Cert manager cluster issuer
-wave 19 PROD: Certificate in traefik ns
-wave 20 Traefik tls store
*At this point all my storage classes, secretes and s3 (seaweedfs) should be functioning. I should also have ingress setup and sites should be accessible at my ip. I should also be able to deploy common helm charts w/ external secrets, k8up pvc restores, cnpg postgres databases restores and ingress.*

### Common helm chart
-wave 14 external secrets (also, cnpg, k8up)
-wave 15 k8up restore
-wave 15 cnpg barman object store
-wave 16 k8up backup + schedule
-wave 16 cnpg restore bucket cleanup job
-wave 17 cnpg cluster
-wave 18 cnpg backup
-wave 25 Traefik ingressroute

## Core apps
-wave -20 Sync common helm apps
-wave 20 Authelia db restore (common)
-wave 20 Harbor
-wave 20 Common: external secrets
-wave 21 Authelia
-wave 21 lldap
-wave 21 Traefik
-wave 21 Forgejo
-wave 22 lldap bootstrap
-wave 22 Checkpoint health job for:
  - authelia
  - traefik
  - lldap
  - Harbor
  - Forgejo
-wave 23 Dashy deployment
*At this point all my core k8s utilities should be run and confirmed with the test app. Everything should be accessible with my traefik lb ip. Data should be restored from k8up backups which are in the minio. I should also be able to deploy common helm charts w/ ingress (authelia/traefik) and k8up pvc backups/schedules.*

## Other apps
-wave 25 apps/site
-wave 25 apps/media
*At this point all my 'fun' apps should be running and accessible.*
