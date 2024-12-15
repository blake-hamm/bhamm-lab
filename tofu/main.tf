# data "vault_kv_secret_v2" "example" {
#   mount = "secret"
#   name  = "example/foo"
# }
# output "example_secret_output" {
#   value     = data.vault_kv_secret_v2.example
#   sensitive = true
# }

data "local_file" "ssh_public_key" {
  filename = "/home/${var.user}/.ssh/id_ed25519.pub"
}

resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "ceph_fs"
  node_name    = "aorus"

  source_raw {
    data = <<-EOF
    #cloud-config
    set_hostname: debian-vm
    users:
      - default
      - name: ${var.user}
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.ssh_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    runcmd:
        - apt update
        - apt install -y qemu-guest-agent net-tools
        - timedatectl set-timezone America/Denver
        - sed -i 's/^#Port 22/Port 4185/' /etc/ssh/sshd_config
        - systemctl restart ssh
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - echo "done" > /tmp/cloud-config.done
    EOF

    file_name = "cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_download_file" "latest_debian_12_bookworm_qcow2_img" {
  content_type = "iso"
  datastore_id = "ceph_fs"
  node_name    = "aorus"
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  file_name    = "debian-12-generic-amd64.qcow2.img"
}

resource "proxmox_virtual_environment_vm" "debian_vm_template" {
  name      = "debian"
  node_name = "aorus"
  vm_id     = 100
  tags      = ["debian"]

  started         = true
  template        = true
  stop_on_destroy = true

  agent {
    enabled = true
  }

  initialization {
    datastore_id = "ceph_pool"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 6144
    floating  = 1
  }

  disk {
    datastore_id = "ceph_pool"
    file_id      = proxmox_virtual_environment_download_file.latest_debian_12_bookworm_qcow2_img.id
    interface    = "scsi0"
    size         = 15
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

  serial_device {
    device = "socket"
  }
}

resource "proxmox_virtual_environment_vm" "k3s_master" {
  count     = var.count_k3s_master
  name      = "k3s-master-${count.index}"
  node_name = var.k3s_nodes[count.index % length(var.k3s_nodes)]
  vm_id     = 110 + count.index
  tags      = ["debian", "k3s", "k3s-master"]

  started         = true
  stop_on_destroy = true
  reboot          = true
  migrate         = true

  agent {
    enabled = true
  }

  clone {
    datastore_id = "ceph_pool"
    node_name    = "aorus"
    vm_id        = 100
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 10240
    floating  = 1
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

  serial_device {
    device = "socket"
  }

  depends_on = [proxmox_virtual_environment_vm.debian_vm_template]
}

resource "proxmox_virtual_environment_haresource" "k3s_master_ha" {
  count       = var.count_k3s_master
  depends_on  = [proxmox_virtual_environment_vm.debian_vm_template, proxmox_virtual_environment_vm.k3s_master]
  resource_id = "vm:${110 + count.index}"
  state       = "started"
  group       = "k3s-master"
  comment     = "Managed by Tofu"
}

# resource "proxmox_virtual_environment_vm" "k3s" {
#   count     = 3
#   name      = "k3s-master-${count.index}"
#   node_name = "precision"
#   clone {
#     node_name = "aorus"
#     datastore_id = "ceph"
#     vm_id        = 100
#   }
#   tags = ["k3s","master","k3s-master"]
# }

# resource "proxmox_virtual_environment_vm" "opnsense" {
#   name       = "opnsense"
#   node_name  = "aorus"
#   started    = false
#   on_boot    = false
#   boot_order = ["scsi0"]

#   cpu {
#     cores = 2
#     type  = "x86-64-v2-AES"
#   }

#   memory {
#     dedicated = 6144
#   }

#   disk {
#     datastore_id = "ceph_pool"
#     interface    = "scsi0"
#     size         = 15
#   }
#   cdrom {
#     enabled = true
#     file_id = "ceph:iso/OPNsense-24.7-dvd-amd64.iso"
#     interface="ide0"
#   }

#   network_device {
#     model  = "virtio"
#     bridge = "vmbr1"
#   }

#   network_device {
#     model  = "virtio"
#     bridge = "vmbr2"
#   }

# }