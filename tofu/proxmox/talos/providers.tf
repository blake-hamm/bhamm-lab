terraform {
  required_version = ">= 1.7"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.73.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.7.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
  }
}