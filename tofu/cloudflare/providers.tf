terraform {
  required_version = ">= 1.7" # For open tofu
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}