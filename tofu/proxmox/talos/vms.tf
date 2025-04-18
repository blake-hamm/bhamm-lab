resource "proxmox_virtual_environment_vm" "this" {
  for_each = local.all_nodes

  name      = each.value.hostname
  node_name = each.value.host_node
  vm_id     = each.value.vm_id
  tags = [
    "talos",
    "tofu",
    var.environment,
    each.value.machine_type,
    each.value.host_node,
  ]
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  started         = true
  on_boot         = true
  stop_on_destroy = true
  migrate         = true

  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores = var.cpu_cores_master
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = 1
  }

  network_device {
    model   = "virtio"
    bridge  = var.network_bridge
    trunks  = var.network_trunks
    vlan_id = var.vlan_id
    mtu     = var.mtu
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    file_format  = "raw"
    size         = each.value.disk_size
    file_id      = proxmox_virtual_environment_download_file.this.id
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }


  initialization {
    datastore_id = var.vm_datastore_id
    dns {
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.network_gateway
      }
      ipv6 {
        address = "dhcp"
      }
    }
  }
}
