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
  content_type       = "iso"
  datastore_id       = "ceph_fs"
  node_name          = "aorus"
  url                = "https://cloud.debian.org/images/cloud/bookworm/20250210-2019/debian-12-generic-amd64-20250210-2019.qcow2"
  file_name          = "debian-12-generic-amd64-20250210-2019.img"
  checksum           = "56c236142b9e1427862dad62f7dfa727287599d361e7b71c22e3bd1c10e8a9f958fb820576cb5ec239bcb186cc2134b5742120c0b95aeeda68ed867bf206889a"
  checksum_algorithm = "sha512"
  upload_timeout     = 2400
}

resource "proxmox_virtual_environment_vm" "debian_vm_template" {
  name      = "debian"
  node_name = "aorus"
  vm_id     = 100
  tags      = ["tofu", "debian"]

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
    size         = 10
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

  serial_device {
    device = "socket"
  }
}
