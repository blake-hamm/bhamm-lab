terraform {
  required_version = ">= 1.7" # For open tofu
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.73.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  insecure = true
  ssh {
    agent    = true
    username = "bhamm"
    node {
      name    = "aorus"
      address = "10.0.20.11"
      port    = "4185"
    }
    node {
      name    = "antsle"
      address = "10.0.20.12"
      port    = "4185"
    }
    node {
      name    = "super"
      address = "10.0.20.13"
      port    = "4185"
    }
  }
}