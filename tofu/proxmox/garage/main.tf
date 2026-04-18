provider "proxmox" {
  endpoint = var.proxmox_url
  insecure = true
  ssh {
    agent    = true
    username = "root"
    node {
      name    = "japan"
      address = "10.0.20.15"
      port    = "4185"
    }
  }
}

data "proxmox_file" "nixos_image" {
  content_type = "iso"
  datastore_id = "cephfs"
  node_name    = var.node_name
  file_name    = "nixos.img"
}

resource "proxmox_virtual_environment_vm" "garage" {
  name          = "garage"
  node_name     = var.node_name
  vm_id         = var.vm_id
  tags          = ["tofu", "garage", "nixos", "japan"]
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "ovmf"

  started         = true
  on_boot         = true
  stop_on_destroy = true

  agent {
    enabled = true
    trim    = true
    type    = "virtio"
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
    floating  = 0
  }

  network_device {
    model   = "virtio"
    bridge  = var.net_bridge
    trunks  = var.net_trunks
    vlan_id = var.net_vlan_id
    mtu     = var.net_mtu
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id = var.datastore_boot
    type         = "4m"
  }

  # Main OS disk: raw image placed on lvm
  disk {
    datastore_id = var.datastore_boot
    file_id      = data.proxmox_file.nixos_image.id
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    size         = var.boot_size
    file_format  = "raw"
  }

  # HBA PCIe passthrough
  dynamic "hostpci" {
    for_each = var.hba_pcie_ids
    content {
      device = "hostpci${hostpci.key}"
      id     = hostpci.value
      pcie   = true
      rombar = true
    }
  }

  # Serial device for boot debugging (matches console=ttyS0 kernel param)
  serial_device {
    device = "socket"
  }

  # Cloud-Init on ide2 (standard Proxmox cloud-init location)
  initialization {
    datastore_id = var.datastore_boot
    interface    = "ide2"
    ip_config {
      ipv4 {
        address = "${var.garage_ip}/24"
        gateway = "10.0.20.2"
      }
    }
    dns {
      domain  = ""
      servers = ["10.0.9.2"]
    }
    user_account {
      username = var.initial_user
      keys     = var.ssh_keys
    }
  }
}
