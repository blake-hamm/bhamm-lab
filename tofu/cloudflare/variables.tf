variable "cloudflare_api_token" {
  description = "API token for cloudflare auth."
  type        = string
}


variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "truenas_bucket_name" {
  description = "The name of the R2 bucket for TrueNAS."
  type        = string
  default     = "truenas-backups"
}

variable "truenas_bucket_location" {
  description = "The location of the R2 bucket for TrueNAS."
  type        = string
  default     = "wnam"
}

variable "truenas_bucket_storage_class" {
  description = "The storage class of the R2 bucket for TrueNAS."
  type        = string
  default     = "Standard"
}
