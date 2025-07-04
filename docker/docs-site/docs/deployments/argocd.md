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
-wave 2 Monitor
-wave 2 Vault
-wave 2 CloudnativePG
-wave 3 Checkpoint job for vault health
-wave 3 External Secrets
-wave 4 Vault secret store
-wave 5 Checkpoint job for secrets store health
-wave 6 garage (k8up restore from gcp)
-wave 7 Checkpoint job for garage health
-wave 8 Cert manager external dns challenge
-wave 9 Test helm
*At this point all my storage classes, secretes and garage should be functioning. Also, I should have a valid cert for my cloudflare website. I should also be able to deploy common helm charts w/ external secrets, k8up pvc restores and cnpg postgres databases restores.*

## Sync (core)
-wave -1 Sync common helm apps
-wave 0 Authelia db restore from garage (internal)
-wave 0 Argo Workflows/Events
-wave 0 Harbor
-wave 0 Common: external secrets
-wave 1 Checkpoint job for authelia db health
-wave 1 Common: cnpg cluster restores
-wave 1 Common: k8up pvc restores
-wave 2 Authelia
-wave 2 lldap
-wave 2 Traefik
-wave 2 Forgejo
-wave 3 Checkpoint health job for:
  - authelia
  - traefik
  - lldap
  - Argo workflows/events
  - Harbor
  - Forgejo
-wave 4 Dashy deployment
-wave 4 Test app deployment
*At this point all my core k8s utilities should be run and confirmed with the test app. Everything should be accessible with my traefik lb ip. Data should be restored from k8up backups which are in the minio. I should also be able to deploy common helm charts w/ ingress (authelia/traefik) and k8up pvc backups/schedules.*

## PostSync (apps)
-wave 0 Common: k8up pvc backups/schedule
-wave 0 Common: Traefik ingress routes w/ Authelia
-wave 1 Media deployments
*At this point all my 'fun' apps should be running and accessible.*
