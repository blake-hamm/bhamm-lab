# Stabilize seaweedfs backups
x Decide architecture
x Ensure seaweedfs is paused during backup
x After backup sync argocd
x Refactor seaweedfs backup to cluster workflow templates
  x Create k8up resource template
  x Adjust common helm to leverage argo
  - Setup stable s3 credentials (stretch)
  x Test k8up restore with blue seaweedfs
    x Ensure argo workflow rbac
  x Setup blue cluster
    x Immich
    x Jellyfinn
    x Servarr
    x Enable Backups (common all)
    x Confirm blue common backups (swfs)
    x Merge with main so that blue = main
    x Forgejo
    x Confirm swfs backups
  x Ensure cnpg restore has backup plan
x Blue deployment (and switch)
  x Restore seaweedfs w/out snapshot - https://github.com/k8up-io/k8up/issues/867
  x Ensure common k8up restores don't need snapshot
  x PR to main (for common enhancements)
- Green deployment on feature/finalize-dr
  - Ensure base restore
  - Ensure core restore
  - Ensure apps restore
- Update DR docs (k8up/restic snapshots)

# Fix cephfs
- Install fuse3 on talos worker images
- Leverage fuse3 features in cephfs storage class
- Test with forgejo + k8up backup

# Deploy 'nice to haves'
- Finance tracker - https://actualbudget.org/
- CRM for leads - https://github.com/jontitmus-code/SuiteCRM8_docker/tree/master
- Routing to 'public' net (for aubs)
  - Deploy multiple traefik instances with argocd applicationset
    - ex: https://grok.com/share/c2hhcmQtMw%3D%3D_eb8fd6b4-8f40-438e-a65e-bddf01f15f28

# Start building website
- Setup Hugo - https://github.com/adityatelange/hugo-PaperMod
- Expose hugo homepage at bhamm-lab.com/
- Deploy docs at bhamm-lab.com/docs/
- Deploy lighthearted at bhamm-lab.com/lighthearted/
- Deploy portfolio links at bhamm-lab.com/portfolio/
- Deploy portfolio links at bhamm-lab.com/about/
- Deploy portfolio links at bhamm-lab.com/contact/
- Deploy blogs at bhamm-lab.com/blogs/

# Prep for exposure
- Add kubernetes metrics
- Switch from dev/prod to blue/green
- Refactor gitea actions as argo workflows
- Traefik
  - setup new ip for dmz
  - block *.bhamm-lab.com from public
  - Setup split dns (wildcard internal, www. dmz)

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
- Setup talos dmz block except ip
- Cloudflare:
  - Use proxy
- Opnsense:
  - port forward traefik prod ip to dmz
  - geo filter
  - only allow cloudflare ip's
  - expose 443 on dmz
- Consider Zeek

# Backup/storage observability
- Create k8up backup dashboard w/ alerts
- Add dashy links for zfs exporter and snapraid/mergerfs grafana
- Setup zfs exporter and grafana - https://github.com/aroberts/ansible-role-zfs_exporter
- Setup snapraid/mergerfs grafana - https://github.com/ljmerza/snapraid-collector

# Refactor internal coms
- Change harbor s3 integration to use internal minio svc instead of traefik ingress
- Try argocd w/ gitea internal svc
- Change frequency of dashy pings

# Troubleshot
```bash
From root@aorus.bhamm-lab.com Sun May 04 00:00:04 2025
Envelope-to: root@aorus.bhamm-lab.com
Delivery-date: Sun, 04 May 2025 00:00:04 -0600
From: root@aorus.bhamm-lab.com (Cron Daemon)
To: root@aorus.bhamm-lab.com
Subject: Cron <root@aorus> snapraid scrub --plan 22 --older-than 8
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit
X-Cron-Env: <SHELL=/bin/sh>
X-Cron-Env: <HOME=/root>
X-Cron-Env: <PATH=/usr/bin:/bin>
X-Cron-Env: <LOGNAME=root>
Date: Sun, 04 May 2025 00:00:01 -0600

/bin/sh: 1: snapraid: not found
```

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

# AI
- Switch to garage https://garagehq.deuxfleurs.fr/documentation/cookbook/kubernetes/
- Setup with talos - https://github.com/siderolabs/talos/discussions/10286
- Transtion amd operator to use custom docker image - https://instinct.docs.amd.com/projects/gpu-operator/en/latest/drivers/precompiled-driver.html
- Create node taint to deny scheduling to gpu vm
- Deploy openwebui - https://github.com/open-webui/helm-charts/tree/main/charts/open-webui (with ollama)

# Finish
- Switch to nfs csi driver - https://github.com/kubernetes-csi/csi-driver-nfs
- Switch vm zfs name (and confirm prod backups)
- Make forgejo ha - https://code.forgejo.org/forgejo-helm/forgejo-helm/src/branch/main/docs/ha-setup.md
- Expose hubble and/or setup cilium prom/grafana metrics
- Setup kubernetes metrics in talos
- Setup cilium monitoring
- Ensure HA with node affinity towards vm hosts (aorus, antsle, super)
- Leverage redis operator
- Install proxmox cloud controller
- Argo event/workflow for terraform/ansible and decom gitea actions
- Fix TZ on all services
- Make ha with 3 replicas for all services
- Switch to cilium
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
  - Setup repo mirroring with public images
  - Setup argo workflow to handle this
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
# Polish
x Adjust common ingress route sync
x Ensure base has authelia, treafik, lldap, certs as well
x Ensure
  x Add loki (w/ seaweedfs)
  x Add alloy
  x Argo artifacts (w/ seaweedfs)
  x Argo common (combine events/workflows)
x Ensure monitor/ingress for all base:
  x Argo
  x Argocd
  x Vault
  x Grafana
  x Prometheus
  x Authelia
  x Seaweedfs (UI/s3)
  x Traefik
  x Test
x Deploy core
  x harbor
  x forgejo
  x dashy (and update links)
x Configure manually w/ backups
  x Authelia
  x Forgejo
    x Ensure webhook sa has necessary permissions
  x Harbor
x Deploy docs site/media under 'apps'
  x Config servarr (trashguides)
x Green seaweedfs:
  x Remove seaweedfs and pvc
  x Add log pvc
  x Adjust values for filerdb3 w/ idx pvc
  x Ensure functional (loki logs, cnpg, k8up backups)
  x Backup offsite

# Stabilize
x Ensure green points to main
x Destroy green
x Ceanup ceph kubernetes pool
x Redeploy green
x Finalize storage
  x Ensure talos has storage accessible
  x Setup local path provisioner with kustomize
  x Have cnpg use local path
  x Deploy seaweedfs
    x Ensure PushSecret for s3 creds
    x Ensure offsite backups
  x Transition all s3 usage to seaweedfs (k8up, cnpg)
  x Remove ceph rgw completely
  x Decommission rclone
x Ensure blue cluster restore test cnpg/pvc
x Build 'kill switch' workflow
  x Remove ns/pvc
  x Remove argocd apps
x Ensure green cnpg can have backup & restore
x Cleanup offsite restic backups
x Troubleshoot test restore/backup in morning (confirmed bucket needs to be empty?)
  x Verify test db timestamp table
  x Remove full test common cnpg
  x Watch filer logs
  x Add test common cnpg with restore/backup
  x Confirm test db is updated (might be missing one ts)
  x RCA: cnpg `ScheduleBackup` had immediate: true for immediate backup, this would occur prior to the cluster being setup, causing a failure
x Troubleshoot check/prune/backup jobs
  x Seems okay for now, need to track...

# Refactor cluster
x Setup ceph rgw (replace with rclone s3 server)
- Setup green deployment
  x Talos deployment
  x Sync all ns and 'external-secrets' in terraform w/ sops
x Config argocd
  x ArgoCD app health - https://argo-cd.readthedocs.io/en/stable/operator-manual/health/#argocd-app
  x Adjust sync waves and add phases (hooks)
  x Switch to nfs csi
x Run backups
x Setup blue deployment (should restore cleanly w/out intervention)

# Refactor backups/storage
x Add pvc dashy link
x Deploy second minio tenant w/ nfs storage
x Backup to minio on nfs
x Test backup/restore
x Adjust forgejo storage to minio (retain pvc)
x Use nfs for immich
x Setup nfs minio backup to gcp
x Test dev environment and restore backups
x Update backup docs
x Rename talos vm zfs data
x Update ip addresses for prod
x Remove minio legacy
x Config harbor
x Add forgejo webhook
x Config servarr
  x radarr
  x sonarr
  x flaresolverr
  x prowlarr
  x qbittorrent
x Update secrets for servarr stack and connect
x Ensure qbittorrent functions correctly
x Add minio grafana
x Update dashy links for minio

# Deploy docs site
x Create ci/cd with argo workflows to deploy when docs change
x Update docs flow and make less AI slop
  x Add photo of rack
x Create architecture diagram
x Update software architecture
x Update backup docs
x Update deployment docs
x Update operations docs
x Update security docs
x Add AI docs
x Add docs link to dashy
x ADHOC: Fix backups
  x Add prunes/checks to local backup schedule
  x Compression w/ restic (need to test)
  x Add k8up prometheus/grafana
  x Check loki logs (ex: k8up, minio)
  x Delete servarr download/media backups from k8up
  x Delete pvc on nfs not in cluster
  x Balance mergerfs

# Servarr stack
x Review hacks/default.bak
x Setup nfs on aorus
x Deploy nfs storage class
x Add vpn credentials for gluten
x Deploy
  x Jellyfin
  x Unpackarr
  x Prowlarr
  x Sonarr
  x qbittorent
  x radarr
x Add dashy links

# Fix issues
x Switch to cilium
x Deploy dev cluster w/ cilium (before argocd dp)
x Adjust vm sizing in dev (3 master, 3 workers, less ram/more cpu)
x Add taints for gpu/master nodes
x Switch to talos
x Confirm prod on talos is g2g
  x Confirm test cnpg minio backup w/ workflow
  x Setup vault oidc
x Remove prod k3s
x Migrate tofu state files to prod minio
x Manage local kubeconfig file automagically
x Fully replace example with test
x Update dashy links
  x Remove old grafana dashboards
x Cleanup repo + merge pr
  x media
  x cicd
x After merge
  x Adjust harbor altogether and db restore/backup
    x Setup oidc and disable other logins
    x Setup docker proxy
    x Setup robot creds
    x Ensure example docker image working
  x Adjust forgejo git user, repo, webhook and db restore/backup
    x Adjust oidc/disable admin
    x Setup repo mirror
    x Add ssh key
    x Setup webhook
  x Adjust authelia db restore/backup
  x Adjust immich altogether and db restore/backups
  x Adjust test common branch

# Create argo sops workflow
x Create argo event source for gitea webhook
x Test gitea argo event source
x Expose argo workflows and add to dashy w/ oidc
x Create argo sensor filtering changes in ./docker directory to trigger workflow
x Argo workflow to build, tag, sign and push image to harbor (for example)
x Refactor to be more dynamic based on dockerfiles changed
x Add gitea status ping for commit
x Sops workflow docker image
x Argo event when changes to sops file
x Argo workflow to deploy changes
x Send back to gitea somehow?

# Setup container registry
x SPIKE: find container registry - use gitea
x Test with 'example docker'
  x Test manually with local docker commands and pat (push changes) - in gitea
  x Deploy harbor (better features including mirroring)
    x Setup database and secrets in common chart
    x Deploy helm chart w/ external db and minio creds
    x Configure oidc
    x Configure ingress
  x Confirm bash script with harbor
  x Switch to 'release/*' branch (dev has no gitea action runner)
  x Update sops secret with harbor robot credentials

# First yt video prep
x Deploy dashy https://github.com/lissy93/dashy?tab=readme-ov-file
  x Deployment
  x Configmap
  x svc
  x Ingressroute

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
