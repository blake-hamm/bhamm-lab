variable "proxmox_url" {
  description = "URL for proxmox"
  type        = string
  default     = "https://10.0.20.11:8006"
}

variable "datastore_iso" {
  description = "Datastore for iso"
  default     = "cephfs"
  type        = string
}

variable "node_name" {
  description = "Node to deploy to"
  default     = "method"
  type        = string
}

variable "pbs_url" {
  description = "URL of the Proxmox Backup Server ISO to download"
  type        = string
  default     = "https://enterprise.proxmox.com/iso/proxmox-backup-server_4.0-1.iso"
}

variable "pbs_file" {
  description = "Filename of the Proxmox Backup Server ISO"
  type        = string
  default     = "proxmox-backup-server_4.0-1.iso"
}

variable "vm_id" {
  description = "The virtual machine id"
  type        = number
  default     = 198
}

variable "boot_size" {
  description = "The size of the boot disk in gigabytes"
  type        = number
  default     = 32
}

variable "cpu_cores" {
  description = "The number of cpu cores for the vm"
  type        = number
  default     = 4
}

variable "memory" {
  description = "The amount of memory for the vm"
  type        = number
  default     = 4096
}

variable "net_bridge" {
  description = "The network bridge"
  type        = string
  default     = "vmbr0"
}

variable "net_trunks" {
  description = "The network trunks"
  type        = string
  default     = "1;20;30"
}

variable "net_mtu" {
  description = "The network mtu"
  type        = number
  default     = 9000
}

variable "datastore_boot" {
  description = "The datastore for the boot disk"
  type        = string
  default     = "lvm"
}
