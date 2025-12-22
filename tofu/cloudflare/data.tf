data "cloudflare_zones" "bhamm_lab" {
  name = "bhamm-lab.com"
  account = {
    id = var.cloudflare_account_id
  }
}