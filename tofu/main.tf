data "vault_kv_secret_v2" "example" {
  mount = "secret"
  name  = "example/foo"
}
output "example_secret_output" {
  value     = data.vault_kv_secret_v2.example
  sensitive = true
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
    bridge = "vmbr0"
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "aorus"

  url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

# resource "proxmox_vm_qemu" "opnsense" {
#   name        = "opnsense"
#   agent       = 0
#   pxe         = true
#   target_node = "aorus"
#   vm_state    = "started"
#   boot        = "order=scsi1,scsi0"
#   network {
#     bridge    = "vmbr0"
#     firewall  = false
#     link_down = false
#     model     = "virtio"
#   }
#   disk {
#     slot = "scsi0"
#     size    = "10G"
#     storage = "local"
#     type    = "disk"
#   }
#   disk {
#     slot = "scsi1"
#     storage = "local"
#     type    = "cdrom"
#     iso = "iso/OPNsense-24.7-dvd-amd64.iso"
#   }
# }