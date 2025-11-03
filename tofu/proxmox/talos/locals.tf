locals {
  # Gather metadata to download talos image
  schematic                  = file("${path.module}/config/schematic.yaml")
  schematic_id               = jsondecode(data.http.schematic_id.response_body)["id"]
  schematic_intel_gpu        = file("${path.module}/config/schematic-intel-gpu.yaml")
  schematic_id_intel_gpu     = length(var.intel_gpu_worker_id) > 0 ? jsondecode(data.http.schematic_id_intel_gpu[0].response_body)["id"] : null
  schematic_amd_gpu          = file("${path.module}/config/schematic-amd-gpu.yaml")
  schematic_id_amd_gpu       = length(var.amd_gpu_worker_id) > 0 ? jsondecode(data.http.schematic_id_amd_gpu[0].response_body)["id"] : null
  schematic_amd_framework    = file("${path.module}/config/schematic-amd-framework.yaml")
  schematic_id_amd_framework = length(var.metal_amd_framework_workers) > 0 ? jsondecode(data.http.schematic_id_amd_framework[0].response_body)["id"] : null
  # Talos vm config
  master_nodes = [
    for idx in range(var.count_master) : {
      hostname       = "${var.environment}-talos-master-${idx}"
      ip             = format(var.master_ip_format, idx)
      machine_type   = "controlplane"
      machine_tier   = "standard"
      host_node      = var.proxmox_nodes[idx].name
      vm_id          = var.master_vm_id_start + idx
      cpu            = var.cpu_cores_master
      disk_size      = var.disk_size_master
      disk_size_user = null
      memory         = floor(var.memory_base_master * var.proxmox_nodes[idx].multiplier)
      vip            = var.vip
      taint          = null
      vm_tag         = null
      hostpci        = {}
      interface      = "eth0"
      is_vm          = true
      schematic_id   = local.schematic_id
    }
  ]

  intel_gpu_worker_node = [{
    hostname       = "${var.environment}-talos-worker-intel-gpu"
    ip             = format(var.worker_ip_format, var.count_worker)
    machine_type   = "worker"
    machine_tier   = "accelerated"
    host_node      = "method"
    vm_id          = var.worker_vm_id_start + var.count_worker
    cpu            = var.cpu_cores_worker
    disk_size      = var.disk_size_worker
    disk_size_user = null
    memory         = floor(var.memory_base_worker * var.proxmox_nodes[1].multiplier)
    vip            = null
    taint          = { key = "intel.com/gpu", effect = "NoSchedule" }
    vm_tag         = "intel-gpu"
    hostpci        = var.intel_gpu_worker_id
    interface      = "eth0"
    is_vm          = true
    schematic_id   = local.schematic_id_intel_gpu
  }]

  amd_gpu_worker_node = [{
    hostname       = "${var.environment}-talos-worker-amd-gpu"
    ip             = format(var.worker_ip_format, var.count_worker + 1)
    machine_type   = "worker"
    machine_tier   = "accelerated"
    host_node      = "method"
    vm_id          = var.worker_vm_id_start + var.count_worker + 1
    cpu            = var.cpu_cores_worker
    disk_size      = var.disk_size_worker
    disk_size_user = var.disk_size_amd_gpu_worker
    memory         = 30518
    vip            = null
    taint          = { key = "amd.com/gpu", effect = "NoSchedule" }
    vm_tag         = "amd-gpu"
    hostpci        = var.amd_gpu_worker_id
    interface      = "eth0"
    is_vm          = true
    schematic_id   = local.schematic_id_amd_gpu
  }]

  metal_amd_framework_nodes = [
    for name, config in var.metal_amd_framework_workers : {
      hostname       = "${var.environment}-talos-worker-${name}"
      ip             = config.ip
      machine_type   = "worker"
      machine_tier   = "accelerated"
      host_node      = name
      taint          = { key = config.taint.key, effect = config.taint.effect }
      is_vm          = false
      vm_id          = null
      cpu            = null
      disk_size      = null
      disk_size_user = null
      memory         = null
      vip            = null
      vm_tag         = null
      hostpci        = null
      interface      = var.metal_amd_framework_interface
      schematic_id   = local.schematic_id_amd_framework
    }
  ]

  worker_nodes = concat(
    [
      for idx in range(var.count_worker) : {
        hostname       = "${var.environment}-talos-worker-${idx}"
        ip             = format(var.worker_ip_format, idx)
        machine_type   = "worker"
        machine_tier   = "standard"
        host_node      = var.proxmox_nodes[idx].name
        vm_id          = var.worker_vm_id_start + idx
        cpu            = var.cpu_cores_worker
        disk_size      = var.disk_size_worker
        disk_size_user = null
        memory         = floor(var.memory_base_worker * var.proxmox_nodes[idx].multiplier)
        vip            = null
        taint          = null
        vm_tag         = null
        hostpci        = {}
        interface      = "eth0"
        is_vm          = true
        schematic_id   = local.schematic_id
      }
    ],
    length(var.intel_gpu_worker_id) > 0 ? local.intel_gpu_worker_node : [],
    length(var.amd_gpu_worker_id) > 0 ? local.amd_gpu_worker_node : [],
    length(var.metal_amd_framework_workers) > 0 ? local.metal_amd_framework_nodes : [],
  )

  all_nodes = {
    for node in concat(local.master_nodes, local.worker_nodes) :
    node.hostname => node
  }

  cluster_endpoint = [for node in local.master_nodes : node.ip][0]

  # Cilium config files
  cilium_values  = file("${path.module}/config/cilium-values.yaml")
  cilium_install = file("${path.module}/config/cilium-install.yaml")
}