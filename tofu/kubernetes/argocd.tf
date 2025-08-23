resource "helm_release" "argocd" {
  depends_on = [
    kubernetes_secret.this
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
  wait = true
}

resource "kubectl_manifest" "argo_apps" {
  depends_on = [helm_release.argocd]
  yaml_body  = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${var.environment}-base
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/blake-hamm/bhamm-lab.git
    targetRevision: ${var.branch_name}
    path: kubernetes/manifests/base
    directory:
      recurse: true
      include: "{**all.yaml,**${var.environment}.yaml}"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    syncOptions:
      - ApplyOutOfSyncOnly=true
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 10m
YAML
}