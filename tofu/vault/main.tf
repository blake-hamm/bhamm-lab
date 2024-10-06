resource "vault_mount" "kvv2" {
  path        = "kvv2"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine mount"
}
data "vault_kv_secret_v2" "example" {
  mount = vault_mount.kvv2.path
  name  = "secret/data/example"
}