variable "proxmox_url" {
  default = "https://10.0.20.11:8006"
  type    = string
}

variable "user" {
  default = "bhamm"
  type    = string
}

variable "gitea_public_key" {
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn6e5VeOkY4WcW0wPmz8uWj+yd+kulj7Ls7upTdKFUO gitea@bhamm-lab.com"
  type    = string
}
