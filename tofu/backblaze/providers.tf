terraform {
  required_version = ">= 1.7"
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.12"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "b2" {
  application_key_id = var.b2_application_key_id
  application_key    = var.b2_application_key
}
