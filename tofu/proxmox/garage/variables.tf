variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "node_name" {
  default = "japan"
  type    = string
}

variable "datastore_boot" {
  description = "Datastore for the VM boot disk"
  default     = "lvm"
  type        = string
}

variable "vm_id" {
  default = 300
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

variable "net_mtu" {
  default = 9000
  type    = number
}

variable "garage_ip" {
  default = "10.0.20.21"
  type    = string
}

variable "garage_vlan30_ip" {
  default = "10.0.30.21"
  type    = string
}

variable "hba_pcie_ids" {
  description = "PCIe slot addresses for the HBA controller"
  type        = list(string)
  default     = ["0000:03:00.0"]
}

variable "initial_user" {
  description = "Username for cloud-init injection"
  default     = "bhamm"
  type        = string
}

variable "ssh_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com"
  ]
}
