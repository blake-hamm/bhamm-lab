resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "master" {
  cluster_name         = var.environment
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for node in local.master_nodes : node.ip]
  endpoints            = [for node in local.master_nodes : node.ip]
}

data "talos_machine_configuration" "this" {
  for_each         = local.all_nodes
  cluster_name     = var.environment
  cluster_endpoint = var.cluster_endpoint
  talos_version    = var.talos_version
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = each.value.machine_type == "controlplane" ? [
    templatefile("${path.module}/config/master.yaml.tftpl", {
      hostname       = each.value.hostname
      node_name      = each.value.host_node
      cluster_name   = var.environment
      cilium_values  = local.cilium_values
      cilium_install = local.cilium_install
    })
    ] : [
    templatefile("${path.module}/config/worker.yaml.tftpl", {
      hostname     = each.key
      node_name    = each.value.host_node
      cluster_name = var.environment
    })
  ]
}
