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

# Download the NixOS generic cloud image (QCOW2).
# Fallback: if 25.11 is not yet available, switch to nixos-unstable.
resource "proxmox_virtual_environment_download_file" "nixos_cloud" {
  content_type   = "iso"
  datastore_id   = var.datastore_iso
  node_name      = var.node_name
  url            = var.nixos_url
  file_name      = var.nixos_file
  upload_timeout = 2400
}

resource "proxmox_virtual_environment_vm" "garage" {
  name          = "garage"
  node_name     = var.node_name
  vm_id         = var.vm_id
  tags          = ["tofu", "garage", "nixos"]
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
    model  = "virtio"
    bridge = var.net_bridge
    trunks = var.net_trunks
    mtu    = var.net_mtu
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id = var.datastore_boot
    type         = "4m"
  }

  disk {
    datastore_id = var.datastore_boot
    file_id      = proxmox_virtual_environment_download_file.nixos_cloud.id
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    size         = var.boot_size
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

  # Cloud-Init
  initialization {
    datastore_id = var.datastore_boot
    ip_config {
      ipv4 {
        address = "${var.garage_ip}/24"
        gateway = "10.0.20.1"
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
