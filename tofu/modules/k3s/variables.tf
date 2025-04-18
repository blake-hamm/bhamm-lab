variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "count_k3s_master" {
  description = "Number of k3s master nodes"
  type        = number
}

variable "count_k3s_worker" {
  description = "Number of k3s worker nodes"
  type        = number
}

variable "k3s_master_nodes" {
  description = "List of Proxmox nodes and their memory multipliers"
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

variable "k3s_worker_nodes" {
  description = "List of Proxmox nodes and their memory multipliers"
  type = list(object({
    name       = string
    multiplier = number
  }))
  default = [
    { name = "super", multiplier = 1.6 },
    { name = "antsle", multiplier = 1 },
  ]
}

variable "enable_gpu_worker" {
  type        = bool
  default     = false
  description = "Controls whether to create the GPU worker VM"
}

variable "k3s_gpu_worker_node" {
  description = "Proxmox node for gpu workers"
  type        = string
  default     = "aorus"
}

variable "k3s_gpu_worker_id" {
  description = "Id for gpu worker (used for vm id and ip address)"
  type        = number
  default     = 5
}

variable "gpu_cpu_cores" {
  description = "CPU cores for gpu worker"
  type        = number
  default     = 6
}

variable "k3s_gpu_memory" {
  description = "Memory for gpu worker in MB"
  type        = number
  default     = 30720 # 30 by default
}

variable "k3s_host_gpu_id" {
  description = "Proxmox host gpu id"
  type        = string
  default     = "0000:09:00.0"
}

variable "k3s_host_gpu_audio_id" {
  description = "Proxmox host gpu audio id"
  type        = string
  default     = "0000:09:00.1"
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

variable "clone_datastore_id" {
  description = "Datastore ID for cloning"
  type        = string
  default     = "ceph_pool"
}

variable "clone_node_name" {
  description = "Proxmox node name for cloning"
  type        = string
  default     = "aorus"
}

variable "clone_vm_id" {
  description = "Source VM ID for cloning"
  type        = number
  default     = 100
}

variable "vm_disk_datastore_id" {
  description = "Datastore ID for VM disks"
  type        = string
  default     = "ceph_pool"
}

variable "initialization_datastore_id" {
  description = "Datastore ID for initialization"
  type        = string
  default     = "ceph_pool"
}

variable "user_data_file_id" {
  description = "Cloud-init user data file ID"
  type        = string
  default     = "ceph_fs:snippets/cloud-config.yaml"
}

variable "cpu_cores_master" {
  description = "Number of CPU cores for master nodes"
  type        = number
}

variable "cpu_cores_worker" {
  description = "Number of CPU cores for worker nodes"
  type        = number
}

variable "memory_dedicated_base" {
  description = "Base memory allocation in MB"
  type        = number
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 50
}