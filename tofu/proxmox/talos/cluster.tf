resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.environment
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for node in local.master_nodes : node.ip]
  endpoints            = [for node in local.master_nodes : node.ip]
}

resource "terraform_data" "cilium_bootstrap_inline_manifests" {
  input = [
    {
      name     = "cilium-bootstrap"
      contents = local.cilium_install
    },
    {
      name = "cilium-values"
      contents = yamlencode({
        apiVersion = "v1"
        kind       = "ConfigMap"
        metadata = {
          name      = "cilium-values"
          namespace = "kube-system"
        }
        data = {
          "values.yaml" = local.cilium_values
        }
      })
    }
  ]
}

data "talos_machine_configuration" "this" {
  for_each         = local.all_nodes
  cluster_name     = var.environment
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  talos_version    = var.talos_version
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    templatefile("${path.module}/config/common.yaml.tftpl", {
      node_name    = each.value.host_node
      cluster_name = var.environment
      hostname     = each.key
      ip           = each.value.ip
      mtu          = var.mtu
      gateway      = var.network_gateway
      vip          = each.value.vip
      interface    = each.value.interface
      taint        = try(each.value.taint, "")
      vlan_id      = var.vlan_id
    }), each.value.machine_type == "controlplane" ?
    templatefile("${path.module}/config/master.yaml.tftpl", {
      # kubelet = var.cluster.kubelet
      extra_manifests = jsonencode(var.extra_manifests)
      # api_server = var.cluster.api_server
      inline_manifests = jsonencode(terraform_data.cilium_bootstrap_inline_manifests.output)
    }) : ""
  ]
}

resource "talos_machine_configuration_apply" "vms" {
  depends_on = [proxmox_virtual_environment_vm.this]
  for_each   = { for k, v in local.all_nodes : k => v if v.is_vm }

  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.this[each.key]]
  }
}

resource "talos_machine_configuration_apply" "bare_metal" {
  depends_on = [talos_machine_configuration_apply.vms]
  for_each   = { for k, v in local.all_nodes : k => v if !v.is_vm }

  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/nvme0n1"
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.vms,
    talos_machine_configuration_apply.bare_metal
  ]
  node                 = [for node in local.master_nodes : node.ip][0]
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.vms,
    talos_machine_configuration_apply.bare_metal,
    talos_machine_bootstrap.this
  ]
  skip_kubernetes_checks = false
  client_configuration   = data.talos_client_configuration.this.client_configuration
  control_plane_nodes    = [for node in local.master_nodes : node.ip]
  worker_nodes           = [for node in local.worker_nodes : node.ip]
  endpoints              = data.talos_client_configuration.this.endpoints
  timeouts = {
    read = "10m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]
  node                 = var.vip
  client_configuration = talos_machine_secrets.this.client_configuration
  timeouts = {
    read = "1m"
  }
}
