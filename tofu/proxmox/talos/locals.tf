locals {
  # Gather metadata to download talos image
  schematic    = file("${path.module}/config/schematic.yaml")
  schematic_id = jsondecode(data.http.schematic_id.response_body)["id"]
  image_id     = "${local.schematic_id}_${var.talos_version}"

  # Talos vm config
  master_nodes = [
    for idx in range(var.count_master) : {
      hostname     = "${var.environment}-talos-master-${idx}"
      ip           = format(var.master_ip_format, idx)
      machine_type = "controlplane"
      host_node    = var.proxmox_nodes[idx].name
      vm_id        = var.master_vm_id_start + idx
      cpu          = var.cpu_cores_master
      disk_size    = var.disk_size_master
      memory       = floor(var.memory_base_master * var.proxmox_nodes[idx].multiplier)
    }
  ]

  worker_nodes = [
    for idx in range(var.count_worker) : {
      hostname     = "${var.environment}-talos-worker-${idx}"
      ip           = format(var.worker_ip_format, idx)
      machine_type = "worker"
      host_node    = var.proxmox_nodes[idx].name
      vm_id        = var.worker_vm_id_start + idx
      cpu          = var.cpu_cores_worker
      disk_size    = var.disk_size_worker
      memory       = floor(var.memory_base_worker * var.proxmox_nodes[idx].multiplier)
    }
  ]

  all_nodes = {
    for node in concat(local.master_nodes, local.worker_nodes) :
    node.hostname => node
  }

  # Cilium config files
  cilium_values  = file("${path.module}/config/cilium-values.yaml")
  cilium_install = file("${path.module}/config/cilium-install.yaml")
}