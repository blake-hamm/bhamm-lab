variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
  default     = "deep-contact-445917-i9"
}

variable "region" {
  description = "The default region for resources"
  type        = string
  default     = "us-central1"
}

variable "sops_key_file_path" {
  description = "Path to save the generated key file."
  type        = string
  default     = "./result/gcp-sops-sa.json"
}

variable "openrouter_key_file_path" {
  description = "Path to save the OpenRouter Vertex AI service account key file."
  type        = string
  default     = "./result/openrouter-vertex-sa.json"
}
