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
- Deploy 'prod' cluster
- Deploy core
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
  - cert manager
  - traefik
    - expose argocd
  - velero
  x external secrets
  - convert jobs to argo workflows (sops and ceph check)
- Setup helm chart for my apps (external secrets, traefik, pvc, pg)
  - example nginx with helm
  - Document disaster recovery (DR)
  - Test DR with pvc and pg (manually)
x Seperate out terraform code for k3s
- Use namespaces
x Enable k3s vlan and other networking rules
- Update docs

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
- Convert sync sops to vault job as argo workflow
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
