resource "proxmox_virtual_environment_download_file" "pbs_iso" {
  node_name      = var.node_name
  datastore_id   = var.datastore_iso
  content_type   = "iso"
  url            = var.pbs_url
  file_name      = var.pbs_file
  upload_timeout = 2400
}

resource "proxmox_virtual_environment_vm" "pbs" {
  name          = "proxmox-backup-server"
  tags          = ["tofu", "proxmox-backup-server"]
  node_name     = var.node_name
  vm_id         = var.vm_id
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  started         = true
  on_boot         = true
  stop_on_destroy = true

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
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

  disk {
    datastore_id = var.datastore_boot
    size         = var.boot_size
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    file_format  = "raw"
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.pbs_iso.id
    interface = "ide3"
  }

  boot_order = ["scsi0", "ide3"]
}