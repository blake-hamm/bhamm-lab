# Adjust storage config
x Switch swfs to local storage
x Switch cnpg to ceph for ha
x Wait for swfs backup
x Deploy blue cluster (for harbor and testing)
x Switch traffic, test and destroy green cluster
x Merge branch with main
x Deploy green cluster with new storage config
x Switch traffic, test and destroy blue
x Troubleshoot remaining orphaned data cleanup
- Create argo workflow to cleanup ceph
x Setup smartctl exporter - https://github.com/prometheus-community/smartctl_exporter

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
- Traefik
  - Setup new traefik instance (external)
  - Setup cloudflare tunnel - https://github.com/adyanth/cloudflare-operator/blob/main/docs/getting-started.md

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
- Deploy argocd image updateder - https://argocd-image-updater.readthedocs.io/en/stable/ (or renovate)
- Setup talos dmz block except ip
- Cloudflare:
  - Use proxy
- Opnsense:
  - geo filter
- Consider Zeek

# Refactor internal coms
- Change frequency of dashy pings

# Upgrade servarr
- https://configarr.de/docs/installation/kubernetes/
- Bazarr
- Lidarr
- Readarr
- Grafana

- Ensure *.bhamm-lab.com is accessible from aubs phone/laptops

# Finish
- Expose hubble and/or setup cilium prom/grafana metrics
- Install proxmox cloud controller
- Fix TZ on all services
- Further restrict proxmox users (ansible, tofu remove)
- Install awx - https://github.com/ansible-community/awx-operator-helm
- Document secret rotation
- Deploy
  - netbootxyz
  - home assistant
  - Integrate proxmox UI into traefik
- More fine grain vault security access
- Consider refactoring proxmox ansible to terraform
  - ACL's
  - Users
  - Groups
  - HA groups
  - Storage (pbs,nfs)
- Implement devsec.os_hardening
- Implement debian firewall rules
- Setup CI/CD for other services
  - Ansible bare metal
  - Ansible opnsense
  - Terrafrom gcp
- Consider argocd application sets - https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Use-Cases/
- Install renovate bot - https://docs.renovatebot.com/modules/platform/gitea/
  - Setup repo mirroring with public images
  - Setup argo workflow to handle this
- audit and rotate secrets
- Automated opnsense backups - https://www.zenarmor.com/docs/network-security-tutorials/opnsense-security-and-hardening-best-practice-guide#regularly-backup-and-protect-backup-files
- Deploy elasticsearch operator
  - https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-eck.html
  - replace zenarmor db in opnsense
- lynis audit - https://cisofy.com/lynis/#how-it-works
- blackbox exporter - https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml
  - omada equipment
    - snmp exporter
- traefik waf https://plugins.traefik.io/plugins/628c9eadffc0cd18356a9799/modsecurity-plugin
- k8up - https://grafana.com/grafana/dashboards/20166-k8up/ (stretch)
- kube bench - https://github.com/aquasecurity/kube-bench
