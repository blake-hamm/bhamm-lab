variable "talos_version" {
  description = "Talos version to use"
  type        = string
  default     = "v1.11.2"
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
  description = "Environment name (e.g., blue, green)"
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
    { name = "indy", multiplier = 1.5 },
    { name = "method", multiplier = 1.4 },
    { name = "stale", multiplier = 1 },
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

variable "mtu" {
  description = "MTU of network"
  type        = number
  default     = 9000
}

variable "vm_datastore_id" {
  description = "Datastore ID for vm's in Proxmox"
  type        = string
  default     = "lvm"
}

variable "file_datastore_id" {
  description = "Datastore ID for files in Proxmox"
  type        = string
  default     = "cephfs"
}

variable "proxmox_file_node" {
  description = "Node to download the talos image to"
  type        = string
  default     = "method"
}

variable "cpu_cores_master" {
  description = "Number of CPU cores for master nodes"
  type        = number
  default     = 2
}

variable "cpu_cores_worker" {
  description = "Number of CPU cores for worker nodes"
  type        = number
  default     = 6
}

variable "memory_base_master" {
  description = "Base memory allocation in MB for master nodes"
  type        = number
  default     = 6144
}

variable "memory_base_worker" {
  description = "Base memory allocation in MB for worker nodes"
  type        = number
  default     = 14336
}

variable "disk_size_amd_gpu_worker" {
  description = "Disk size in GB for the AMD GPU worker user disk"
  type        = number
  default     = 50
}

variable "disk_size_master" {
  description = "Boot disk for master in gb"
  type        = number
  default     = 40
}

variable "disk_size_worker" {
  description = "Boot disk for work in gb"
  type        = number
  default     = 60
}

variable "vip" {
  description = "VIP endpoint for cluster"
  type        = string
}

variable "extra_manifests" {
  description = "Extra kubernetes manifests to deploy."
  type        = list(string)
  default     = []
}

variable "intel_gpu_worker_id" {
  description = "A list of PCI IDs for the Intel GPU and related devices for passthrough."
  type        = list(string)
  default     = []
}

variable "amd_gpu_worker_id" {
  description = "List of AMD GPU worker IDs"
  type        = list(string)
  default     = []
}

variable "metal_amd_framework_workers" {
  description = "A map of framework amd metal workers to add to the cluster."
  type = map(object({
    ip = string
    taint = object({
      key    = string
      effect = string
    })
  }))
  default = {}
}

variable "metal_amd_framework_disk_path" {
  description = "Disk path for bare metal installations"
  type        = string
  default     = "/dev/nvme0n1"
}

variable "metal_amd_framework_interface" {
  description = "Network interface for bare metal installations"
  type        = string
  default     = "enp191s0"
}

variable "bios_type" {
  description = "BIOS type for VMs"
  type        = string
  default     = "seabios"
}
