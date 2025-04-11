terraform {
  required_version = ">= 1.7"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.36.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.19.0"
    }
  }
}