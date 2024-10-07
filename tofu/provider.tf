terraform {
  required_version = ">= 1.7" # For open tofu
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.4.0"
    }
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.1-rc4"
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
  pm_api_url = var.proxmox_url
}