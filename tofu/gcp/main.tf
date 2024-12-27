resource "google_storage_bucket" "backup" {
  name          = var.bucket_name
  location      = var.bucket_location
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# Create service account for Argo Workflows
resource "google_service_account" "argo_workflows" {
  account_id   = var.service_account_id
  display_name = "Argo Workflows Backup Service Account"
  description  = "Service account for Argo Workflows to handle GCS backups"
}

# Grant storage object admin permissions to the service account
resource "google_storage_bucket_iam_member" "argo_workflows_storage_admin" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.argo_workflows.email}"
}

# Create service account key
resource "google_service_account_key" "argo_workflows_key" {
  service_account_id = google_service_account.argo_workflows.name
}

# Store credentials in Vault
resource "vault_generic_secret" "argo_workflows_creds" {
  path = "secret/core/argo-workflows"

  data_json = jsonencode({
    "gcp_credentials.json" = base64decode(google_service_account_key.argo_workflows_key.private_key),
    "bucket_name"          = google_storage_bucket.backup.name,
    "project_id"           = var.project_id
  })
}
