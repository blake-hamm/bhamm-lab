# Secure network
x Reset AP
x Change opnsense playbook
  x process group_vars
  x apply common rules and group_var rules
x Change firewall rules
  x guest can access iot
  x higher priority for guest

# Documentation
- Organize: Architecture, Deployments, Operations, Security and Compliance, and Disaster Recovery
- Build out docs
- Deploy to gh pages

# Proxmox/ceph cluster
- Setup new debian machine w/ ansible
- Optimize and confirm networking
- Setup proxmox config w/ proxmox
- Deploy cluster
- Consider refactoring ansible to terraform

# k3s cluster
- Setup helm chart for my apps (external secrets, traefik, pvc, pg)
- Use namespaces
- Configure minio
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
