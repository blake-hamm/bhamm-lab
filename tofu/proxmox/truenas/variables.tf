variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "datastore_iso" {
  description = "The datastore for ISO images."
  default     = "cephfs"
  type        = string
}

variable "node_name" {
  description = "The Proxmox node to deploy to."
  default     = "method"
  type        = string
}

variable "truenas_url" {
  description = "The URL for the TrueNAS ISO."
  default     = "https://download.sys.truenas.net/TrueNAS-SCALE-Fangtooth/25.04.2.4/TrueNAS-SCALE-25.04.2.4.iso"
  type        = string
}

variable "truenas_file" {
  description = "The filename for the TrueNAS ISO."
  default     = "TrueNAS-SCALE-25.04.2.4.iso"
  type        = string
}

variable "vm_id" {
  description = "Proxmox vm id."
  type        = number
  default     = 199
}

variable "boot_size" {
  description = "Boot volume size"
  type        = number
  default     = 20
}

variable "cpu_cores" {
  description = "The number of CPU cores for the VM."
  default     = 4
  type        = number
}

variable "memory" {
  description = "The amount of memory for the VM in MB."
  default     = 10240
  type        = number
}

variable "net_bridge" {
  description = "The network bridge for the VM."
  default     = "vmbr0"
  type        = string
}

variable "net_trunks" {
  description = "The network trunks for the VM."
  type        = string
  default     = "1;20;30"
}

variable "net_mtu" {
  description = "The MTU for the VM network interface."
  default     = 9000
  type        = number
}

variable "datastore_boot" {
  description = "The datastore for the boot disk."
  default     = "lvm"
  type        = string
}

variable "sata_pcie_ids" {
  description = "A list of PCI IDs for the sata devices for passthrough."
  type        = list(string)
  default     = ["0000:01:00.0"]
}
