terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.85.0"
    }
    # vault = {
    #   source  = "hashicorp/vault"
    #   version = "3.25.0"
    # }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# provider "vault" {
#   add_address_to_env = true
#   skip_child_token   = true
#   auth_login {
#     path = "auth/approle/login"

#     parameters = {
#       role_id   = var.vault_role_id
#       secret_id = var.vault_secret_id
#     }
#   }
# }
