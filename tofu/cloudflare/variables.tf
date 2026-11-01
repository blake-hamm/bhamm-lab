variable "cloudflare_api_token" {
  description = "API token for cloudflare auth."
  type        = string
}


variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "tunnel_name" {
  description = "The name of the Cloudflare Zero Trust tunnel."
  type        = string
  default     = "bhamm-lab"
}

variable "tunnel_secret" {
  description = "Base64 Cloudflare tunnel secret. Required: CI passes -var sourced from Vault kv external/cloudflare (key: tunnel_secret); operators pass TF_VAR_tunnel_secret or -var with the same Vault value. Intentionally required — a missing value must hard-error, never silently rotate the live tunnel secret."
  type        = string
}
