# Talos
When deploying talos, we leverage open tofu which orchestates the following steps:
- Curl talos schematic id given version and schematic
- Download given schematic id to proxmox
- Deploy master/worker vms
- Configure talos
- Deploy bootstrap charts (metallb, cilium and ceph)


To deploy talos run these commands:
```bash
# First deploy vm's and bootstrap the cluster
tofu -chdir=tofu/proxmox/talos init
tofu -chdir=tofu/proxmox/talos workspace select -or-create=true test
tofu -chdir=tofu/proxmox/talos plan -var-file=test.tfvars
tofu -chdir=tofu/proxmox/talos apply -var-file=test.tfvars

# Then deploy the minimum required for kubernetes
export KUBECONFIG=../../tofu/proxmox/talos/result/kube-config-test.yaml
export KUBE_CONFIG_PATH=../../tofu/proxmox/talos/result/kube-config-test.yaml
tofu -chdir=tofu/kubernetes init
tofu -chdir=tofu/kubernetes workspace select -or-create=true test
tofu -chdir=tofu/kubernetes plan -var 'environment=test' -var 'branch_name=feature/refactor-cluster'
tofu -chdir=tofu/kubernetes apply -var 'environment=test' -var 'branch_name=feature/refactor-cluster'

# To destroy
export KUBECONFIG=./tofu/proxmox/talos/result/kube-config-test.yaml
argo submit   --from workflowtemplate/kill-switch   --namespace argo   --serviceaccount workflow-admin --entrypoint cleanup
tofu -chdir=tofu/proxmox/talos workspace select -or-create=true test
tofu -chdir=tofu/proxmox/talos destroy -var-file=test.tfvars
```

```bash
# To sync argocd apps
export KUBECONFIG=./tofu/proxmox/talos/result/kube-config-test.yaml
kubectl config set-context --current --namespace=argocd
argocd app get test-base --refresh

# To connect with talosctl
export TALOSCONFIG=./tofu/proxmox/talos/result/talos-config-test.yaml
talosctl dashboard
```

## Admin config recovery (lost laptop / fresh machine)

`result/kube-config-<env>.yaml` and `result/talos-config-<env>.yaml` are **not** managed by tofu (the `local_file` resources were removed); they are disposable derived credentials. Everything needed to re-mint them (the Talos CA + admin client cert/key) lives in the `talos_machine_secrets` resource inside state — the `tofu-state` bucket key `env:/prod/proxmox/talos/terraform.state` (prod workspace; see [OpenTofu](../operations/tofu.md)), which is covered by the ceph-rgw→Garage→B2 nightly backup (see [Backups](../backups/index.md)).

```bash
# 1. S3 credentials for the tofu-state bucket
export VAULT_ADDR=https://vault.bhamm-lab.com
vault login -method=oidc -role=default
export AWS_ACCESS_KEY_ID=$(vault kv get -field=s3_access_key secret/data/core/ceph)
export AWS_SECRET_ACCESS_KEY=$(vault kv get -field=s3_secret_key secret/data/core/ceph)

# 2. Clone the repo and connect to the prod workspace
git clone <repo-url> && cd bhamm-lab
tofu -chdir=tofu/proxmox/talos init -input=false
tofu -chdir=tofu/proxmox/talos workspace select prod

# 3. VIP + control-plane IPs (from prod.tfvars, not hardcoded)
grep -E '^(vip|master_ip_format|count_master) +=' tofu/proxmox/talos/prod.tfvars
# e.g. vip = "10.0.30.30", master_ip_format = "10.0.30.6%d" x 3 -> 10.0.30.61-63

# 4. Re-mint the talosconfig from talos_machine_secrets in state
#    (attribute names: client_configuration.ca_certificate / .client_certificate / .client_key)
tofu -chdir=tofu/proxmox/talos state pull | python3 -c '
import json, sys
s = json.load(sys.stdin)
r = [x for x in s["resources"] if x["type"] == "talos_machine_secrets"][0]
cc = r["instances"][0]["attributes"]["client_configuration"]
open("ca.pem", "w").write(cc["ca_certificate"])
open("client-cert.pem", "w").write(cc["client_certificate"])
open("client-key.pem", "w").write(cc["client_key"])
'

# 5. Assemble the talosconfig (fill <vip> / <cp-ip-N> from step 3)
cat > tofu/proxmox/talos/result/talos-config-prod.yaml <<EOF
context: prod
contexts:
  prod:
    endpoints:
      - https://<vip>:50000
    nodes:
      - <cp-ip-1>
      - <cp-ip-2>
      - <cp-ip-3>
    talos:
      ca: |
$(sed 's/^/        /' ca.pem)
      cert: |
$(sed 's/^/        /' client-cert.pem)
      key: |
$(sed 's/^/        /' client-key.pem)
EOF

# 6. Mint the kubeconfig
export TALOSCONFIG=tofu/proxmox/talos/result/talos-config-prod.yaml
talosctl kubeconfig --endpoints https://<vip>:6443 --nodes <cp-ip-1> --force-endpoint > tofu/proxmox/talos/result/kube-config-prod.yaml

# 7. Verify
talosctl health
export KUBECONFIG=tofu/proxmox/talos/result/kube-config-prod.yaml
kubectl get nodes
```

After a CA rotation or machine-secrets regeneration, re-run steps 4–6 — any copies of the old talosconfig/kubeconfig anywhere else are dead then.

## Rolling Reboot After CPU Changes

Talos does not hot-grow CPU. After `tofu apply` changes a VM's core count, reboot each worker one at a time for the guest to see it:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force
talosctl reboot -n <node-ip>
kubectl wait --for=condition=Ready node/<node> && kubectl uncordon <node>
```

## Bare Metal Framework Nodes

Framework Desktop nodes with AMD Strix Halo APUs are deployed as bare-metal workers via `talos_machine_configuration_apply.bare_metal`. Their USB4 mesh networking configuration is declared in the `.tfvars` file:

```hcl
metal_amd_framework_workers = {
  nose = {
    ip            = "10.0.30.78"
    taint         = { key = "amd.com/gpu", effect = "NoSchedule" }
    usb4_bus_path = "0-2.0"
    usb4_mesh_ip  = "10.30.0.78"
    usb4_peer_ip  = "10.30.0.79"
  }
  tail = {
    ip            = "10.0.30.79"
    taint         = { key = "amd.com/gpu", effect = "NoSchedule" }
    usb4_bus_path = "1-2.0"
    usb4_mesh_ip  = "10.30.0.79"
    usb4_peer_ip  = "10.30.0.78"
  }
}
```

This drives the `thunderbolt` / `thunderbolt-net` kernel modules and the point-to-point `/32` interface configuration applied to each node. See [Strix Halo](../ai/strix-halo.md) for details.

## Create talos iso
```bash
# To get id:
curl -X POST --data-binary @tofu/proxmox/talos/config/schematic-amd-framework.yaml https://factory.talos.dev/schematics
# Which can populate an iso that can be uploaded to piKVM:
# https://factory.talos.dev/image/<id>/v1.11.2/metal-amd64.iso

# To upgrade a bare metal node:
talosctl upgrade --nodes 10.0.30.79 \
  --image  factory.talos.dev/metal-installer/<id>:v1.11.2 \
  --wait --debug

# To remove a node from a cluster
talosctl -n 10.0.30.79 reset

# To get disk and volume status info
talosctl -n 10.0.30.79 get disks -o yaml
talosctl -n 10.0.30.79 get volumestatus -o yaml

# To reboot
talosctl reboot -n 10.0.30.78

# View all resources
talosctl get rd -n 10.0.30.78
```