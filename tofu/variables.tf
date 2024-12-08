# variable "vault_role_id" {
#   type = string
# }

# variable "vault_secret_id" {
#   type = string
# }

variable "proxmox_url" {
  default = "https://192.168.69.12:8006"
  type    = string
}

variable "user" {
  default = "bhamm"
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
  default     = ["antsle", "aorus"]
}