resource "proxmox_virtual_environment_vm" "k3s_master" {
  count     = var.count_k3s_master
  name      = "${var.environment}-k3s-master-${count.index}"
  node_name = var.k3s_master_nodes[count.index].name
  vm_id     = var.master_vm_id_start + count.index
  tags = [
    "debian",
    "k3s",
    "k3s-master",
    "tofu",
    var.environment,
    var.k3s_master_nodes[count.index].name,
  ]

  started         = true
  stop_on_destroy = true
  migrate         = true

  initialization {
    datastore_id = var.initialization_datastore_id
    dns {
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = format(var.master_ip_format, count.index)
        gateway = var.network_gateway
      }
    }
    user_data_file_id = var.user_data_file_id
  }

  agent {
    enabled = true
  }

  clone {
    datastore_id = var.clone_datastore_id
    node_name    = var.clone_node_name
    vm_id        = var.clone_vm_id
  }

  cpu {
    cores = var.cpu_cores_master
    type  = "host"
  }

  machine = "q35"

  memory {
    dedicated = floor(var.memory_dedicated_base * var.k3s_master_nodes[count.index].multiplier)
    floating  = 1
  }

  network_device {
    model   = "virtio"
    bridge  = var.network_bridge
    trunks  = var.network_trunks
    vlan_id = var.vlan_id
  }

  serial_device {
    device = "socket"
  }

  disk {
    datastore_id = var.vm_disk_datastore_id
    interface    = "scsi0"
    size         = var.disk_size
  }
}

resource "proxmox_virtual_environment_haresource" "k3s_master_ha" {
  count       = var.count_k3s_master
  depends_on  = [proxmox_virtual_environment_vm.k3s_master]
  resource_id = "vm:${proxmox_virtual_environment_vm.k3s_master[count.index].vm_id}"
  state       = "started"
  group       = "main"
  comment     = "${var.environment} k3s master HA group."
}

resource "proxmox_virtual_environment_vm" "k3s_worker" {
  count      = var.count_k3s_worker
  depends_on = [proxmox_virtual_environment_vm.k3s_master]
  name       = "${var.environment}-k3s-worker-${count.index}"
  node_name  = var.k3s_worker_nodes[count.index].name
  vm_id      = var.worker_vm_id_start + count.index
  tags = [
    "debian",
    "k3s",
    "k3s-worker",
    "tofu",
    var.environment,
    var.k3s_worker_nodes[count.index].name
  ]

  started         = true
  stop_on_destroy = true
  migrate         = true

  initialization {
    datastore_id = var.initialization_datastore_id
    dns {
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = format(var.worker_ip_format, count.index)
        gateway = var.network_gateway
      }
    }
    user_data_file_id = var.user_data_file_id
  }

  agent {
    enabled = true
  }

  clone {
    datastore_id = var.clone_datastore_id
    node_name    = var.clone_node_name
    vm_id        = var.clone_vm_id
  }

  cpu {
    cores = var.cpu_cores_worker
    type  = "host"
  }

  machine = "q35"

  memory {
    dedicated = floor(var.memory_dedicated_base * var.k3s_worker_nodes[count.index].multiplier)
    floating  = 1
  }

  network_device {
    model   = "virtio"
    bridge  = var.network_bridge
    trunks  = var.network_trunks
    vlan_id = var.vlan_id
  }

  serial_device {
    device = "socket"
  }

  disk {
    datastore_id = var.vm_disk_datastore_id
    interface    = "scsi0"
    size         = var.disk_size
  }
}

resource "proxmox_virtual_environment_vm" "k3s_gpu_worker" {
  count      = var.enable_gpu_worker ? 1 : 0
  depends_on = [proxmox_virtual_environment_vm.k3s_master]
  name       = "${var.environment}-k3s-gpu-worker"
  node_name  = var.k3s_gpu_worker_node
  vm_id      = var.worker_vm_id_start + var.k3s_gpu_worker_id
  tags = [
    "debian",
    "k3s",
    "k3s-worker",
    "tofu",
    "gpu",
    var.environment,
    var.k3s_gpu_worker_node
  ]

  started         = true
  stop_on_destroy = true
  migrate         = true

  initialization {
    datastore_id = var.initialization_datastore_id
    dns {
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = format(var.worker_ip_format, var.k3s_gpu_worker_id)
        gateway = var.network_gateway
      }
    }
    user_data_file_id = var.user_data_file_id
  }

  agent {
    enabled = true
  }

  clone {
    datastore_id = var.clone_datastore_id
    node_name    = var.clone_node_name
    vm_id        = var.clone_vm_id
  }

  cpu {
    cores = var.gpu_cpu_cores
    type  = "host"
  }

  machine = "q35"

  memory {
    dedicated = var.k3s_gpu_memory
    floating  = 1
  }

  network_device {
    model   = "virtio"
    bridge  = var.network_bridge
    trunks  = var.network_trunks
    vlan_id = var.vlan_id
  }

  serial_device {
    device = "socket"
  }

  disk {
    datastore_id = var.vm_disk_datastore_id
    interface    = "scsi0"
    size         = 150 # Requires more space
  }

  hostpci {
    device = "hostpci0"
    id     = var.k3s_host_gpu_id
    pcie   = true
    rombar = true
  }

  hostpci {
    device = "hostpci1"
    id     = var.k3s_host_gpu_audio_id
    pcie   = true
    rombar = true
  }

}
