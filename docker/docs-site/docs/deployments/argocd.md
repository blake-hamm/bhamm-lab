# ArgoCD

## Base app
-wave -1 ArgoCD
-wave 0 Ceph (csi)
-wave 0 NFS (csi)
-wave 0 Operators/crds
  - k8up
  - Cert manager
  - Kubernetes metrics
  - Vault
-wave 1 k8up helm
-wave 1 Checkpoint job for storage health
-wave 1 Ceph rgw endpoints
-wave 2 Monitor
-wave 2 Vault
-wave 2 CloudnativePG
-wave 2 rclone s3 pvc
-wave 2 Ceph rgw service
-wave 3 Checkpoint job for vault health
-wave 3 External Secrets
-wave 3 rclone s3 dp
-wave 3 argo events
-wave 4 rclone s3 svc
-wave 4 Vault secret store
-wave 4 Checkpoint job for ceph rgw s3 health
-wave 4 argo eventbus
-wave 5 Checkpoint job for rclone s3 health
-wave 6 deploy argo workflows with ceph rgw s3
-wave 7 Vault secret sync argo workflow
-wave 7 Pipelines app
-wave 8 argo workflow - rclone s3 create buckets (k8up/cnpg)
-wave 8 argo workflow - ceph rgw s3 create buckets (blue/green) [destroy cnpg objects]
-wave 8 nfs common (secrets for k8up restore/backup)
-wave 9 nfs k8up rclone s3 sync/restore from gcp
-wave 9 Test ns
-wave 10 Test cnpg
-wave 10 Test pvc
-wave 11 Test dp
-wave 12 Test CronWorkflow (timestamp on index.html in pvc)
-wave 12 Test svc
-wave 13 Test common (k8up/cnpg backups)
-wave 14 rclone s3 nfs offsite gcs backups
-wave 18 Test CronWorkflow (timestamp on cnpg)
-wave 19 Cert manager external dns challenge and metrics
*At this point all my storage classes, secretes and s3 (ceph rgw and rclone w/ nfs pvc) should be functioning. I should also be able to deploy common helm charts w/ external secrets, k8up pvc restores and cnpg postgres databases restores.*

## Sync (core)
-wave -20 Sync common helm apps
  -wave 14 external-secrets
  -wave 16 cnpg cluster
  -wave 15 k8up restore
  -wave 16 k8up backup/schedule
  -wave 16 ingress
-wave 20 Authelia db restore (common)
-wave 20 Harbor
-wave 20 Common: external secrets
-wave 21 Authelia
-wave 21 lldap
-wave 21 Traefik
-wave 21 Forgejo
-wave 22 Checkpoint health job for:
  - authelia
  - traefik
  - lldap
  - Argo workflows/events
  - Harbor
  - Forgejo
-wave 23 Dashy deployment
*At this point all my core k8s utilities should be run and confirmed with the test app. Everything should be accessible with my traefik lb ip. Data should be restored from k8up backups which are in the minio. I should also be able to deploy common helm charts w/ ingress (authelia/traefik) and k8up pvc backups/schedules.*

## PostSync (apps)
-wave 0 Common: k8up pvc backups/schedule
-wave 0 Common: Traefik ingress routes w/ Authelia
-wave 1 Media deployments
*At this point all my 'fun' apps should be running and accessible.*
