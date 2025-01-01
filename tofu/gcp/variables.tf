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
  default     = "us-central1"
}

variable "argo_service_account_id" {
  description = "The ID for the Argo Workflows service account"
  type        = string
  default     = "argo-workflows-backup"
}

variable "vault_service_account_id" {
  description = "The name of the service account to create."
  type        = string
  default     = "vault-auto-unseal"
}

variable "vault_roles" {
  description = "Roles to assign to the service account."
  type        = list(string)
  default = [
    "roles/cloudkms.admin",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/storage.admin"
  ]
}

variable "vault_key_file_path" {
  description = "Path to save the generated key file."
  type        = string
  default     = "./vault-auto-unseal-sa-key.json"
}
