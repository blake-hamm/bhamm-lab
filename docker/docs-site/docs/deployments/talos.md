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
tofu -chdir=tofu/proxmox/talos workspace select -or-create=true blue
tofu -chdir=tofu/proxmox/talos plan -var-file=blue.tfvars
tofu -chdir=tofu/proxmox/talos apply -var-file=blue.tfvars

# Then deploy the minimum required for kubernetes
export KUBECONFIG=../../tofu/proxmox/talos/result/kube-config-blue.yaml
export KUBE_CONFIG_PATH=../../tofu/proxmox/talos/result/kube-config-blue.yaml
tofu -chdir=tofu/kubernetes init
tofu -chdir=tofu/kubernetes workspace select -or-create=true blue
tofu -chdir=tofu/kubernetes plan -var 'environment=blue' -var 'branch_name=feature/refactor-cluster'
tofu -chdir=tofu/kubernetes apply -var 'environment=blue' -var 'branch_name=feature/refactor-cluster'

# To destroy
export KUBECONFIG=./tofu/proxmox/talos/result/kube-config-blue.yaml
argo submit   --from workflowtemplate/kill-switch   --namespace argo   --serviceaccount workflow-admin --entrypoint cleanup
tofu -chdir=tofu/proxmox/talos workspace select -or-create=true blue
tofu -chdir=tofu/proxmox/talos destroy -var-file=blue.tfvars
```

```bash
# To sync argocd apps
export KUBECONFIG=./tofu/proxmox/talos/result/kube-config-blue.yaml
kubectl config set-context --current --namespace=argocd
argocd app get blue-base --refresh

# To connect with talosctl
export TALOSCONFIG=./tofu/proxmox/talos/result/talos-config-blue.yaml
talosctl dashboard
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