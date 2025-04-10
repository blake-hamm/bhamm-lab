resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "master" {
  cluster_name         = var.environment
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for node in local.master_nodes : node.ip]
  endpoints            = [for node in local.master_nodes : node.ip]
}
