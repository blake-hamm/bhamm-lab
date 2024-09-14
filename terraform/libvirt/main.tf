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
resource "libvirt_pool" "aorus" {
  name = "aorus"
  type = "dir"
  path = "/var/lib/libvirt/pool/aorus"
}

# Define the storage volume for OPNsense Serial Image
resource "libvirt_volume" "opnsense_iso" {
  name   = "opnsense_iso"
  pool   = libvirt_pool.aorus.name
  source = "https://mirrors.ocf.berkeley.edu/opnsense//releases/24.7/OPNsense-24.7-dvd-amd64.iso.bz2"
}

# Define the storage volume for the virtual disk
resource "libvirt_volume" "opnsense_vm_disk" {
  name = "opnsense_vm_disk"
  pool = libvirt_pool.aorus.name
  size = 10240 # 10 GB
}

# Define the domain with SR-IOV network interface passthrough
resource "libvirt_domain" "vm" {
  name   = "opnsense_vm"
  memory = 2048
  vcpu   = 2

  # Attach disk volume
  disk {
    volume_id = libvirt_volume.opnsense_vm_disk.id
  }

  # Attach the OPNsense Serial Image
  disk {
    file = libvirt_volume.opnsense_iso.id
  }

  # Network interfaces with SR-IOV passthrough for each NIC
  network_interface {
    passthrough = "enp5s0"
  }
  network_interface {
    passthrough = "enp6s0"
  }
  network_interface {
    passthrough = "enp7s0"
  }
  network_interface {
    passthrough = "enp8s0"
  }

  # Serial console configuration for headless setup
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
  }
}
