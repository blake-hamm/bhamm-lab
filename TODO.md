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
- Seperate out terraform code for k3s
- Use kustomize and base/core and dev/prod manifests
- Setup helm chart for my apps (external secrets, traefik, pvc, pg)
- Use namespaces
- Configure minio thoroughly
- Document disaster recovery (DR)
- Test DR with pvc and pg (manually)
- Leverage values file

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
- Connect iot devices
  - printer
  - smart light switches/plugs
  - eufy
- Configure dhcp in ansible opnsense

# Finish
- Install mergerfs/snapraid on aorus node
- Configure pbs
- Consider refactoring ansible to terraform
  - ACL's
  - Users
  - Groups
  - HA groups
  - Storage (pbs,nfs)
