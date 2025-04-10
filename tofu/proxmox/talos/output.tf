output "client_configuration" {
  value     = data.talos_client_configuration.this
  sensitive = true
}

output "kube_config" {
  value     = resource.talos_cluster_kubeconfig.this
  sensitive = true
}

output "machine_config" {
  value     = data.talos_machine_configuration.this
  sensitive = true
}

resource "local_file" "talos_config" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "result/talos-config.yaml"
  file_permission = "0600"
}

resource "local_file" "kube_config" {
  content         = resource.talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "result/kube-config.yaml"
  file_permission = "0600"
}
