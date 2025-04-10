provider "proxmox" {
  endpoint = var.proxmox_url
  insecure = true
  ssh {
    agent    = true
    username = "root"
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

provider "helm" {
  kubernetes {
    config_path = "${path.module}/result/kube-config.yaml"
  }
}

provider "kubernetes" {
  config_path = "${path.module}/result/kube-config.yaml"
}

provider "sops" {}
