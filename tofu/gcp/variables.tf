variable "vault_role_id" {
  type = string
}

variable "vault_secret_id" {
  type = string
}

variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "region" {
  description = "The default region for resources"
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "The name of the GCS bucket"
  type        = string
  default     = "bhamm-lab-backups"
}

variable "bucket_location" {
  description = "The location for the GCS bucket"
  type        = string
  default     = "US"
}

variable "service_account_id" {
  description = "The ID for the Argo Workflows service account"
  type        = string
  default     = "argo-workflows-backup"
}
