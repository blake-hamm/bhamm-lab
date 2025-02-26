variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "count_k3s_master" {
  description = "Number of k3s master nodes"
  type        = number
  default     = 3
}

variable "count_k3s_worker" {
  description = "Number of k3s worker nodes"
  type        = number
  default     = 3
}

variable "k3s_nodes" {
  description = "List of Proxmox nodes with their memory multipliers for k3s deployment"
  type = list(object({
    name       = string
    multiplier = number
  }))
  default = [
    { name = "antsle", multiplier = 1 },
    { name = "aorus", multiplier = 1.5 },
    { name = "super", multiplier = 2 },
  ]
}