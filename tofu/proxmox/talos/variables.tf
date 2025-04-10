variable "talos_version" {
  description = "Talos version to use"
  type        = string
  default     = "v1.9.5"
}

variable "talos_factory_url" {
  description = "Factory url to download image from"
  type        = string
  default     = "https://factory.talos.dev"
}

variable "talos_platform" {
  type    = string
  default = "nocloud"
}

variable "talos_arch" {
  type    = string
  default = "amd64"
}

variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "count_master" {
  description = "Number of talos master nodes"
  type        = number
}

variable "count_worker" {
  description = "Number of talos worker nodes"
  type        = number
}

variable "proxmox_nodes" {
  description = "List of Proxmox nodes for talos masters and their memory multipliers"
  type = list(object({
    name       = string
    multiplier = number
  }))
  default = [
    { name = "super", multiplier = 1.6 },
    { name = "aorus", multiplier = 1.4 },
    { name = "antsle", multiplier = 1 },
  ]
}

variable "master_vm_id_start" {
  description = "Starting VM ID for master nodes"
  type        = number
}

variable "worker_vm_id_start" {
  description = "Starting VM ID for worker nodes"
  type        = number
}

variable "master_ip_format" {
  description = "IP address format string for master nodes (e.g., '10.0.30.6%d/24')"
  type        = string
}

variable "worker_ip_format" {
  description = "IP address format string for worker nodes (e.g., '10.0.30.7%d/24')"
  type        = string
}

variable "network_gateway" {
  description = "Network gateway IP"
  type        = string
  default     = "10.0.30.2"
}


variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["10.0.30.1"]
}

variable "vlan_id" {
  description = "VLAN ID for network"
  type        = number
  default     = 30
}

variable "network_bridge" {
  description = "Network bridge name"
  type        = string
  default     = "vmbr0"
}

variable "network_trunks" {
  description = "Network trunk VLANs"
  type        = string
  default     = "1;20;30"
}

variable "vm_datastore_id" {
  description = "Datastore ID for vm's in Proxmox"
  type        = string
  default     = "ceph_pool"
}

variable "file_datastore_id" {
  description = "Datastore ID for files in Proxmox"
  type        = string
  default     = "ceph_fs"
}

variable "proxmox_file_node" {
  description = "Node to download the talos image to"
  type        = string
  default     = "aorus"
}

variable "cpu_cores_master" {
  description = "Number of CPU cores for master nodes"
  type        = number
  default     = 4
}

variable "cpu_cores_worker" {
  description = "Number of CPU cores for worker nodes"
  type        = number
  default     = 2
}

variable "memory_base_master" {
  description = "Base memory allocation in MB for master nodes"
  type        = number
  default     = 8192
}

variable "memory_base_worker" {
  description = "Base memory allocation in MB for worker nodes"
  type        = number
  default     = 16384
}

variable "disk_size_master" {
  description = "Disk size in GB"
  type        = number
  default     = 75
}

variable "disk_size_worker" {
  description = "Disk size in GB"
  type        = number
  default     = 100
}

variable "cluster_endpoint" {
  description = "VIP endpoint for cluster"
  type        = string
  default     = "https://10.0.30.130:6443"
}
