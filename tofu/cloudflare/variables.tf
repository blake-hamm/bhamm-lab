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
