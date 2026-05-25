# Cloudflare Workers AI — dedicated account API token for the Pi coding agent
# Uses account-scoped token (cloudflare_account_token) instead of user-scoped
# Token name follows naming convention: "pi-framework" = Pi on Framework laptop
# Token is consumed externally via sops (secrets.enc.json → Nix → Pi auth.json)

data "cloudflare_account_api_token_permission_groups_list" "workers_ai_read" {
  account_id = var.cloudflare_account_id
  name       = "Workers%20AI%20Read"
  scope      = "com.cloudflare.api.account"
}

data "cloudflare_account_api_token_permission_groups_list" "workers_ai_write" {
  account_id = var.cloudflare_account_id
  name       = "Workers%20AI%20Write"
  scope      = "com.cloudflare.api.account"
}

resource "cloudflare_account_token" "pi_workers_ai" {
  account_id = var.cloudflare_account_id
  name       = "bhamm-lab pi-framework workers-ai"

  policies = [{
    effect = "allow"
    permission_groups = [
      {
        id = data.cloudflare_account_api_token_permission_groups_list.workers_ai_read.result[0].id
      },
      {
        id = data.cloudflare_account_api_token_permission_groups_list.workers_ai_write.result[0].id
      },
    ]
    resources = {
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    }
  }]
}

output "pi_workers_ai_token_value" {
  description = "Sensitive Workers AI API token for Pi coding agent. Add to secrets.enc.json under vault_secrets.external.cloudflare.pi-workers-ai"
  value       = cloudflare_account_token.pi_workers_ai.value
  sensitive   = true
}
