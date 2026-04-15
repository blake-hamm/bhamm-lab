data "sops_file" "this" {
  source_file = "${path.module}/../../../secrets.enc.json"
}

locals {
  nut_password = jsondecode(nonsensitive(data.sops_file.this.raw)).vault_secrets.core.orangepi.password
}
