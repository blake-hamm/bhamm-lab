resource "cloudflare_r2_bucket" "truenas_bucket" {
  account_id    = var.cloudflare_account_id
  name          = var.truenas_bucket_name
  location      = var.truenas_bucket_location
  storage_class = var.truenas_bucket_storage_class
}