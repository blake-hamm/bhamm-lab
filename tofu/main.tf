data "vault_kv_secret_v2" "example" {
  mount = "secret"
  name  = "example/foo"
}
output "example_secret_output" {
  value     = data.vault_kv_secret_v2.example
  sensitive = true
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "aorus"

  url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name      = "test-ubuntu"
  node_name = "aorus"
  started   = false

  agent {
    enabled = false
  }

  initialization {
    datastore_id = "local"
    user_account {
      username = "ubuntu"
    }
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  disk {
    datastore_id = "local"
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = 15
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }
}

resource "proxmox_virtual_environment_vm" "opnsense" {
  name       = "opnsense"
  node_name  = "aorus"
  started    = true
  boot_order = ["scsi0"]

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 6144
  }

  disk {
    datastore_id = "local"
    interface    = "scsi0"
    size         = 15
  }
  # cdrom {
  #   enabled = true
  #   file_id = "local:iso/OPNsense-24.7-dvd-amd64.iso"
  #   interface="ide0"
  # }

  network_device {
    model  = "virtio"
    bridge = "vmbr1"
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr2"
  }

}