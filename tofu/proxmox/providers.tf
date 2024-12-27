terraform {
  required_version = ">= 1.7" # For open tofu
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.4.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.66.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
  }
}

provider "vault" {
  add_address_to_env = true
  skip_child_token   = true
  auth_login {
    path = "auth/approle/login"

    parameters = {
      role_id   = var.vault_role_id
      secret_id = var.vault_secret_id
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
      address = "192.168.69.12"
      port    = "4185"
    }
    node {
      name    = "antsle"
      address = "192.168.69.13"
      port    = "4185"
    }
  }
}