resource "helm_release" "argocd" {
  depends_on = [
    local_file.kube_config
  ]
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.8.2"
  namespace        = "argocd"
  create_namespace = true
  values = [
    templatefile("${path.module}/config/argocd-values.yaml.tftpl", {
      domain = var.environment == "prod" ? "argocd.bhamm-lab.com" : "argocd.dev.bhamm-lab.com"
    })
  ]
}
