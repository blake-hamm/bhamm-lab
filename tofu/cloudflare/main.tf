# Proofs the CI plan gate: this stack is planned (and applied on PR pushes) by
# tofu-cicd with Vault-sourced creds (S5 #322, #372).
resource "cloudflare_zero_trust_tunnel_cloudflared" "static_site" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  tunnel_secret = var.tunnel_secret
}

resource "cloudflare_tiered_cache" "tiered_cache" {
  zone_id = data.cloudflare_zones.bhamm_lab.result[0].id
  value   = "on"
}
