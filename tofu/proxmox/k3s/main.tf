resource "proxmox_virtual_environment_vm" "k3s_master" {
  count     = var.count_k3s_master
  name      = "k3s-master-${count.index}"
  node_name = var.k3s_nodes[count.index].name
  vm_id     = 110 + count.index
  tags = [
    "debian",
    "k3s",
    "k3s-master",
    var.k3s_nodes[count.index].name,
  ]

  started         = true
  stop_on_destroy = true
  migrate         = true

  initialization {
    datastore_id = "ceph_pool"
    dns {
      servers = [
        "1.1.1.1",
        "1.0.0.1"
      ]
    }
    ip_config {
      ipv4 {
        address = "10.0.30.6${count.index}/24"
        gateway = "10.0.30.1"
      }
    }
  }

  agent {
    enabled = true
  }

  clone {
    datastore_id = "ceph_pool"
    node_name    = "aorus"
    vm_id        = 100
  }

  cpu {
    cores = 3
    type  = "host"
  }

  memory {
    dedicated = 12288 * var.k3s_nodes[count.index].multiplier
    floating  = 1
  }

  network_device {
    model   = "virtio"
    bridge  = "vmbr0"
    vlan_id = 30
  }

  serial_device {
    device = "socket"
  }

  disk {
    datastore_id = "ceph_pool"
    interface    = "scsi0"
    size         = 50
  }
}

resource "proxmox_virtual_environment_haresource" "k3s_master_ha" {
  count       = var.count_k3s_master
  depends_on  = [proxmox_virtual_environment_vm.k3s_master]
  resource_id = "vm:${110 + count.index}"
  state       = "started"
  group       = "k3s-master"
  comment     = "k3s master HA group."
}

resource "proxmox_virtual_environment_vm" "k3s_worker" {
  count     = var.count_k3s_worker
  name      = "k3s-worker-${count.index}"
  node_name = var.k3s_nodes[count.index].name
  vm_id     = 120 + count.index
  tags = [
    "debian",
    "k3s",
    "k3s-worker",
    var.k3s_nodes[count.index].name
  ]

  started         = true
  stop_on_destroy = true
  migrate         = true

  initialization {
    datastore_id = "ceph_pool"
    dns {
      servers = [
        "1.1.1.1",
        "1.0.0.1"
      ]
    }
    ip_config {
      ipv4 {
        address = "10.0.30.7${count.index}/24"
        gateway = "10.0.30.1"
      }
    }
  }

  agent {
    enabled = true
  }

  clone {
    datastore_id = "ceph_pool"
    node_name    = "aorus"
    vm_id        = 100
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 12288 * var.k3s_nodes[count.index].multiplier
    floating  = 1
  }

  network_device {
    model   = "virtio"
    bridge  = "vmbr0"
    vlan_id = 30
  }

  serial_device {
    device = "socket"
  }

  disk {
    datastore_id = "ceph_pool"
    interface    = "scsi0"
    size         = 50
  }
}
