variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "region" {
  description = "The default region for resources"
  type        = string
  default     = "us-central1"
}

variable "k8up_service_account_id" {
  description = "The ID for the k8up service account"
  type        = string
  default     = "k8up-backups"
}

variable "sops_key_file_path" {
  description = "Path to save the generated key file."
  type        = string
  default     = "./gcp-sops-sa.json"
}

variable "k8up_key_file_path" {
  description = "Path to save the generated key file."
  type        = string
  default     = "./gcp-k8up-sa.json"
}
