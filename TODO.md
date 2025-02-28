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
x Refactor 'backups'
  x Rename gcp tofu storage/sa to 'backups' (instead of velero)
  x Update k3s deployment with new secret/naming
x Setup helm chart for my apps (external secrets, traefik, pvc, pg)
  x example nginx with helm
  x Annotate pvc for k8up
  x Run k8up backup manually
  x Change pvc data
  x Restore pvc with k8up and confirm data restored
  x Integrate k8up into helm chart
    x argo workflow secret template
    x argo workflow backup step
    x argo workflow prune step
    x argo workflow restore step
x Seperate out terraform code for k3s
x Use namespaces
x Enable k3s vlan and other networking rules
x Update docs
  x Helm chart
  x DR w/ pv and pg
  x Deployment flow
x Remove unused yaml
x Deploy immich

# CI/CD
- Deploy gitea
- Setup pipelines
  - Terraform proxmox (branch-based with storage backend - minio)
  - Ansible k3s (branch-based)
- Dev cluster on PR
- Test DR with pvc and pg (auto)
  - example pvc should be easy
  - Need to develop and prove out pg w/ ceph + volume snapshot
- Convert sync sops to vault job as argo workflow template
  - Trigger from argo event when vault is ready
  - Trigger from gitea on secret changes

# Monitoring
- Node exporter debian ansible playbook
- Refine grafana dashboard config
- Deploy loki
- Setup alerts for nodes and traefik

# Expose bhamm-lab.com
- Spike cf tunnels
- Setup Hugo
- Expose hugo homepage at bhamm-lab.com/
- Deploy docs at bhamm-lab.com/docs/
- Deploy lighthearted at bhamm-lab.com/lighthearted/
- Deploy portfolio links at bhamm-lab.com/portfolio/
- Deploy portfolio links at bhamm-lab.com/about/
- Deploy portfolio links at bhamm-lab.com/contact/
- Opnsense:
  - port forward traefik prod ip to dmz
  - geo filter
  - expose 443 on dmz
- Traefik
  - proxy
  - block *.bhamm-lab.com

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
- Confirm metal to k8s doesn't leave 10gb switch
- Ensure *.bhamm-lab.com is accessible from aubs phone/laptops
- Integrate proxmox with traefik

# Finish
- Deploy
  - docs site
  - vpn
  - netbootxyz
  - home assistant
  - servarr
    - jellyfin
    - flaresolver
  - Integrate proxmox UI into traefik
- Expose docs site and vpn
- Install mergerfs/snapraid on aorus node
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
  - Setup ceph backups (consider decomissioning k8up if volume snapshots work)
  - Configure snapraid/mergerfs
  - Ensure monitoring
  - Expose nfs
  - Create nfs storage class
  - Setup minio tenant with nfs storage class
  - Refactor k8up prune
    - Move generate secret into template with var
    - Make global prune job that doesn't conflict w/ backup schedule
  - Refactor k8up backups to minio
  - Ensure minio backup bucket syncs to gcp
  - Ensure on new cluster, minio bucket is restored first, then deploy backup
- Setup CI/CD for other services
  - Ansible bare metal
  - Ansible opnsense
  - Terrafrom gcp
- Setup service mesh (istio/hashicorp consul)
