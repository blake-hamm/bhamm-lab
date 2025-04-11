
data "sops_file" "this" {
  source_file = "../../secrets.enc.json"
}

locals {
  secret_structure = jsondecode(nonsensitive(data.sops_file.this.raw)).init
  namespaces       = keys(local.secret_structure) # Extract namespace names
  secrets_map = merge([
    for namespace, secrets in local.secret_structure : {
      for secret_name, secret_data in secrets :
      "${namespace}/${secret_name}" => {
        namespace = namespace
        name      = secret_name
        data      = sensitive(tomap(secret_data))
      }
    }
  ]...)
}

resource "kubernetes_namespace" "this" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.key
  }
}

resource "kubernetes_secret" "this" {
  depends_on = [kubernetes_namespace.this]
  for_each   = local.secrets_map

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  data = each.value.data
  type = "Opaque"
}