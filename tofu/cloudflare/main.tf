resource "cloudflare_r2_bucket" "truenas_bucket" {
  account_id    = var.cloudflare_account_id
  name          = var.truenas_bucket_name
  location      = var.truenas_bucket_location
  storage_class = var.truenas_bucket_storage_class
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "static_site" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  tunnel_secret = local.tunnel_secret
}

resource "cloudflare_tiered_cache" "tiered_cache" {
  zone_id = data.cloudflare_zones.bhamm_lab.result[0].id
  value   = "on"
}