resource "proxmox_virtual_environment_vm" "k3s_master" {
  count     = var.count_k3s_master
  name      = "${var.environment}-k3s-master-${count.index}"
  node_name = var.k3s_nodes[count.index].name
  vm_id     = var.master_vm_id_start + count.index
  tags = [
    "debian",
    "k3s",
    "k3s-master",
    var.environment,
    var.k3s_nodes[count.index].name,
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

  memory {
    dedicated = floor(var.memory_dedicated_base * var.k3s_nodes[count.index].multiplier)
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
  count     = var.count_k3s_worker
  name      = "${var.environment}-k3s-worker-${count.index}"
  node_name = var.k3s_nodes[count.index].name
  vm_id     = var.worker_vm_id_start + count.index
  tags = [
    "debian",
    "k3s",
    "k3s-worker",
    var.environment,
    var.k3s_nodes[count.index].name
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

  memory {
    dedicated = floor(var.memory_dedicated_base * var.k3s_nodes[count.index].multiplier)
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