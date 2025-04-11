provider "helm" {}

provider "kubernetes" {}

provider "sops" {}

provider "kubectl" {
  config_path = "../../tofu/proxmox/talos/result/kube-config.yaml"
}