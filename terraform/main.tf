terraform {
  required_version = "1.8.3"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu+ssh://bhamm@192.168.69.12:4185/system?no_verify=1&keyfile=/home/bhamm/.ssh/id_ed25519"
}

# Define the storage pool
resource "libvirt_pool" "default" {
  name = "default"
  type = "dir"
  path = "/var/lib/libvirt/images"
}
