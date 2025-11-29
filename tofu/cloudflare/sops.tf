data "sops_file" "this" {
  source_file = "../../secrets.enc.json"
}

locals {
  tunnel_secret = jsondecode(nonsensitive(data.sops_file.this.raw)).vault_secrets.external.cloudflare.tunnel_secret
}

