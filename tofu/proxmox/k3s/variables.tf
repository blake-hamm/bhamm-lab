variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "count_k3s_master" {
  description = "Number of k3s master nodes"
  type        = number
  default     = 3
}

variable "k3s_nodes" {
  description = "List of Proxmox nodes for k3s deployment"
  type        = list(string)
  default     = ["antsle", "aorus", "super"]
}

variable "count_k3s_worker" {
  description = "Number of k3s worker nodes"
  type        = number
  default     = 3
}