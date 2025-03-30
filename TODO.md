# Setup container registry
- SPIKE: find container registry
- Deploy
- Test with 'example docker'

# First yt video prep
- Deploy dashy https://github.com/lissy93/dashy?tab=readme-ov-file

# Start building website
- Setup Hugo
- Expose hugo homepage at bhamm-lab.com/
- Deploy docs at bhamm-lab.com/docs/
- Deploy lighthearted at bhamm-lab.com/lighthearted/
- Deploy portfolio links at bhamm-lab.com/portfolio/
- Deploy portfolio links at bhamm-lab.com/about/
- Deploy portfolio links at bhamm-lab.com/contact/

# Expose bhamm-lab.com
- Setup alerts for nodes and traefik
- Example Cloud-Native Security Stack:
    Falco: Runtime security for Kubernetes.
    CrowdSec: Block malicious IPs (SSH, web attacks).
    Suricata: Network-layer IDS.
    Trivy: Vulnerability scanning.
    Osquery: Host-level compliance checks.
- falco https://github.com/falcosecurity/charts/tree/master/charts
- crowdsec server
  - integrate with agents
  - integrate with traefik
- clamAV
- Deploy argocd image updateder - https://argocd-image-updater.readthedocs.io/en/stable/
- Spike: explore most secure method
- Setup debian firewall
- Cloudflare:
  - Use proxy
- Opnsense:
  - port forward traefik prod ip to dmz
  - geo filter
  - only allow cloudflare ip's
  - expose 443 on dmz
- Traefik
  - setup new metallb ip for external
  - block *.bhamm-lab.com from public
  - Setup split dns
- Consider Zeek

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
- Transtion amd operator to use custom docker image - https://instinct.docs.amd.com/projects/gpu-operator/en/latest/drivers/precompiled-driver.html
- cloudnative pg monitoring
- Further restrict proxmox users (ansible, tofu remove)
- Install awx - https://github.com/ansible-community/awx-operator-helm
- Use gitea container registry
  - sync sops workflow
- Convert sync sops to vault job as argo workflow template
  - Trigger from argo event when vault is ready
  - Trigger from argo event on secret changes in git
- Document secret rotation
- Refactor argocd projects into 'core', 'default'
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
- Consider refactoring minio to primary storage and k8up sync to gcp
- Audit backups
  - Use example site for continuous backups/gitops updates with argo workflow/k8up/cloudnativepg
  - s3 to s3 backups
  - DR architecture diagram
- Consider argocd application sets - https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Use-Cases/
- Install renovate bot - https://docs.renovatebot.com/modules/platform/gitea/
- Consider using cilium - https://cilium.io/
- audit and rotate secrets
- Automated opnsense backups - https://www.zenarmor.com/docs/network-security-tutorials/opnsense-security-and-hardening-best-practice-guide#regularly-backup-and-protect-backup-files
- Deploy elasticsearch operator
  - https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-eck.html
  - replace zenarmor db in opnsense
- lynis audit - https://cisofy.com/lynis/#how-it-works
- blackbox exporter - https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml
  - omada equipment
    - snmp exporter
- Migrate from k3s to something more robust
  - Confirm monitoring for
    - kube scheduler
    - kube etcd
    - kube controller
    - kube proxy
  - Or this - https://fabianlee.org/2022/07/02/prometheus-installing-kube-prometheus-stack-on-k3s-cluster/
- traefik waf https://plugins.traefik.io/plugins/628c9eadffc0cd18356a9799/modsecurity-plugin
- k8up - https://grafana.com/grafana/dashboards/20166-k8up/ (stretch)
- kube bench - https://github.com/aquasecurity/kube-bench

## Previous
# Install gpu
x Physical install on aorus (replace previous one and remove nic)
  x Adjust nic config
x Setup pcie passthrough
x Setup debian gpu machine for k3s tofu module
x Integrate with k3s
  x add amd gpu operator
  x Leverage in deployment
x Confirm in prod
  x Add monitoring
  - Test pytorch container (too large - need to test in different way)

# Monitoring
x Expose prometheus gui
x Expose grafana gui
  x enable oidc
x Key monitoring
  x Bare metal
    x node exporter
  x k3s
    x Remove ansible node exporter
    x Use k8s-native node exporter
    x api server
    x resources
    x cadviser
    x kube-state
    x calico
    x authelia
    x metallb (need to fork dashboard json and adjust data source)
    x vault
    x cert manager
  x opnsense firewall
    x netflow analyzer
  x traefik/authelia
    x status codes
    x response times
  x ceph
x Node exporter debian ansible playbook
x Deploy loki
  x Leverage minio storage
  x Deploy alloy
x Finalize Prod
  x Merge pr
  x Make release/* branch
    x Fix authelia db (restore from newer snapshot)
    x Fix gitea (unknown)
    x Leverage github as source of truth
    x Somehow skip k3s role in ansible if it's already running and there is no 'force' flag
    X Update prod stuff
      x oidc grafana
      x traefik prometheus/grafana/alertmanager
      x kube-prom-stack
      x loki
      x alloy
      x metallb metrics
      X vault smon
    x Update gitea action
    x Update sops sync branch
  x Collect debian logs (journald) to loki w/ ansible

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
x Deploy gitea
x Create cephfs storage class (for RWM)
x Deploy gitea act runner
x Mirror github to gitea as primary
  x Setup metallb ssh (share lb with traefik)
  x Set github as upstream
x Switch argocd to gitea repo
x Troubleshoot tofu proxmox/k3s when migrating vm (ssh issue) and change ordering of bare metal to (super, aorus, antsle)
x Destory legacy 'prod' once new prod is working properly
x Redploy 'prod' with new setup/cidr
x Restore with k8up and volume snapshots
x Setup gitea properly
x Document restore (immich - db/pvc)
x Restore minio fully
x Migrate tofu state to minio
x Setup gitea pipeline for k3s
  x Terraform proxmox
    x Setup minio tofu backend
    x migrate backend to minio
    x Convert k3s into module
    x Leverage module for prod and dev
  x Ansible
    x Adapt dev
  x Add gitea action token into vault config
  x Ensure on open pr - spin up new k3s cluster and deploy
  x On merge to main
    x tofu/ansible and argocd sync
    x destory dev cluster
x Test DR
  x Deploy manifests
  x Confirm pvc
    x Alter helm chart to require snapshot name and path for recovery
    x example
    x minio (state bucket and keys) - backup from s3 instead
      x Enhance restore template to loop through pvc with k8up annotation
      x Based on list of pvc, restore each one and generate 'folder claimName'
      x Try again with snapshot name
    x immich (library)
    x gitea (shared)
  x Need to develop and prove out pg w/ ceph + volume snapshot
    x common chart deploys volume snapshot directly from ceph
    x Confirm db
      x example (query)
      x immich (login) - TODO: make pvc for config file (contains oidc)
      x gitea (code)
      x authelia (2fa)
x After merge PR, point prod to 'main' branch in all aspects
