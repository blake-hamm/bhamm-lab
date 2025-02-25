# Secure network
x Reset AP
x Change opnsense playbook
  x process group_vars
  x apply common rules and group_var rules
x Change firewall rules
  x guest can access iot
  x higher priority for guest

# Documentation
x Organize:
  x Architecture
  x Deployments
  x Operations
  x Security and Compliance
  x Disaster Recovery
x Build out docs
x Deploy to gh pages

# Proxmox/ceph cluster
x Setup new debian machine w/ ansible
x Optimize and confirm networking
x Setup proxmox config w/ proxmox
x Deploy cluster
x Update docs

# k3s cluster
x Deploy 'prod' cluster
x Deploy core
  x argocd
  x argo-events
  x metallb
  x calico
  x migrate ceph config to argocd (rather than k3s manifests)
  x minio
  x argo-workflows
  x vault
  x lldap
  x cloudnative pg
  x authelia
  x cert manager
  x traefik expose
    x traefik
    x authelia
    x vault
    x argocd
  x velero
  x external secrets
  x convert jobs to argo workflows (sops and ceph check)
  x k8up
- Refactor 'backups'
  - Rename gcp tofu storage/sa to 'backups' (instead of velero)
  - Update k3s deployment with new secret/naming
x Setup helm chart for my apps (external secrets, traefik, pvc, pg)
  x example nginx with helm
  - Annotate pvc for k8up
  - Run k8up backup manually
  - Change pvc data
  - Restore pvc with k8up and confirm data restored
  - Integrate k8up into helm chart (and remove velero)
  - Remove all velero resources
x Seperate out terraform code for k3s
x Use namespaces
x Enable k3s vlan and other networking rules
x Update docs
  - Helm chart
  - DR w/ pv and pg
  - Deployment flow

# CI/CD
- Deploy forego or gitea
- Setup pipelines
  - Ansible bare metal
  - Ansible opnsense
  - Terrafrom gcp
  - Terraform proxmox
  - Ansible k3s
- Dev cluster on PR
- Test DR with pvc and pg (auto)
- Convert sync sops to vault job as argo workflow template
  - Trigger from argo event when vault is ready
  - Trigger from gitea on secret changes

# Monitoring
- Node exporter debian ansible playbook
- Refine grafana dashboard config
- Deploy loki
- Setup alerts for nodes and traefik

# Omada sdn
- Setup 3 wifi networks
  x Polk_Paradise
  x lab-trusted
  - lab-iot
- Deploy omada sdn
- Connect iot devices
  - printer
  - smart light switches/plugs
  - eufy
- Configure dhcp in ansible opnsense

# Finish
- Deploy
  - docs site
  - vpn
  - netbootxyz
  - immich
  - home assistant
  - servarr
    - jellyfin
    - flaresolver
  - Integrate proxmox UI into traefik
- Expose docs site and vpn
- Install mergerfs/snapraid on aorus node
- Integrate proxmox with traefik
- More fine grain vault security access
- Consider refactoring proxmox ansible to terraform
  - ACL's
  - Users
  - Groups
  - HA groups
  - Storage (pbs,nfs)
- Implement devsec.os_hardening
- Implement debian firewall rules
- 3-2-1 backups
  - Configure snapraid/mergerfs
  - Ensure monitoring
  - Expose nfs
  - Create nfs storage class
  - Setup minio tenant with nfs storage class
  - Refactor k8up backups to minio
  - Ensure minio backup bucket syncs to gcp
  - Ensure on new cluster, minio bucket is restored first, then deploy backup
