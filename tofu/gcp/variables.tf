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

variable "velero_service_account_id" {
  description = "The ID for the Velero service account"
  type        = string
  default     = "velero-workflows-backup"
}

variable "vault_service_account_id" {
  description = "The name of the service account to create."
  type        = string
  default     = "vault-auto-unseal"
}

variable "vault_key_file_path" {
  description = "Path to save the generated key file."
  type        = string
  default     = "./gcp-unseal-sa.json"
}

variable "sops_key_file_path" {
  description = "Path to save the generated key file."
  type        = string
  default     = "./gcp-sops-sa.json"
}

variable "velero_key_file_path" {
  description = "Path to save the generated key file."
  type        = string
  default     = "./gcp-velero-sa.json"
}

