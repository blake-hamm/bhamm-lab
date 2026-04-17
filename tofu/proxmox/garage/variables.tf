variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "datastore_iso" {
  default = "cephfs"
  type    = string
}

variable "node_name" {
  default = "japan"
  type    = string
}

variable "nixos_url" {
  description = "NixOS cloud image URL"
  default     = "https://channels.nixos.org/nixos-25.11/nixos-amazon-image-25.11-x86_64-linux.qcow2"
  type        = string
}

variable "nixos_file" {
  description = "Local file name for the downloaded NixOS cloud image"
  default     = "nixos-cloud-25.11.img"
  type        = string
}

variable "vm_id" {
  default = 200
  type    = number
}

variable "boot_size" {
  default = 20
  type    = number
}

variable "cpu_cores" {
  default = 4
  type    = number
}

variable "memory" {
  default = 10240
  type    = number
}

variable "net_bridge" {
  default = "vmbr0"
  type    = string
}

variable "net_trunks" {
  default = "1;20;30"
  type    = string
}

variable "net_mtu" {
  default = 9000
  type    = number
}

variable "datastore_boot" {
  default = "lvm"
  type    = string
}

variable "garage_ip" {
  default = "10.0.20.21"
  type    = string
}

variable "hba_pcie_ids" {
  description = "PCIe slot addresses for the HBA controller"
  type        = list(string)
  default     = ["0000:03:00.0"]
}

variable "initial_user" {
  description = "Username for cloud-init injection (must exist in the cloud image)"
  default     = "bhamm"
  type        = string
}

variable "ssh_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn6e5VeOkY4WcW0wPmz8uWj+yd+kulj7Ls7upTdKFUO gitea@bhamm-lab.com"
  ]
}
