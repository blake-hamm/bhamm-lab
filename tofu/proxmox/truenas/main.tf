resource "proxmox_virtual_environment_download_file" "truenas" {
  content_type   = "iso"
  datastore_id   = var.datastore_iso
  node_name      = var.node_name
  url            = var.truenas_url
  file_name      = var.truenas_file
  upload_timeout = 2400
}

resource "proxmox_virtual_environment_vm" "truenas" {
  name          = "truenas"
  node_name     = var.node_name
  vm_id         = var.vm_id
  tags          = ["tofu", "truenas"]
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

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

  boot_order = ["scsi0", "ide3"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.truenas.id
    interface = "ide3"
  }

  disk {
    datastore_id = var.datastore_boot
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    file_format  = "raw"
    size         = var.boot_size
  }


  dynamic "hostpci" {
    for_each = var.sata_pcie_ids
    content {
      device = "hostpci${hostpci.key}"
      id     = hostpci.value
      pcie   = true
      rombar = true
    }
  }

}
