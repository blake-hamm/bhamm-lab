resource "google_project_iam_member" "storage_service_account_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_kms_key_ring" "backup_key_ring" {
  name       = "${var.bucket_name}-key-ring"
  location   = var.bucket_location
  depends_on = [google_project_iam_member.storage_service_account_kms]
}

resource "google_kms_crypto_key" "backup_crypto_key" {
  name            = "${var.bucket_name}-crypto-key"
  key_ring        = google_kms_key_ring.backup_key_ring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true # Protects the key from accidental deletion
  }
}

resource "google_storage_bucket" "backup" {
  name          = var.bucket_name
  location      = var.bucket_location
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.backup_crypto_key.id
  }

  lifecycle_rule {
    condition {
      age = 120
    }
    action {
      type = "Delete"
    }
  }
}

# Create service account for Argo Workflows
resource "google_service_account" "argo_workflows" {
  account_id  = var.argo_service_account_id
  description = "Service account for Argo Workflows to handle GCS backups"
}

resource "google_project_iam_member" "argo_workflows_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.argo_workflows.email}"
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
# resource "vault_generic_secret" "argo_workflows_creds" {
#   path = "secret/core/argo-workflows"

#   data_json = jsonencode({
#     "gcp_credentials.json" = base64decode(google_service_account_key.argo_workflows_key.private_key),
#     "bucket_name"          = google_storage_bucket.backup.name,
#     "project_id"           = var.project_id
#   })
# }

# Create a Service Account
resource "google_service_account" "vault_sa" {
  account_id   = var.vault_service_account_id
  display_name = "Vault Auto Unseal SA"
}

# Bind roles to the Service Account
resource "google_project_iam_member" "vault_sa_roles" {
  for_each = toset(var.vault_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.vault_sa.email}"
}

resource "google_service_account_key" "vault_sa_key" {
  service_account_id = google_service_account.vault_sa.name

  provisioner "local-exec" {
    command = "echo '${self.private_key}' | base64 --decode > ${var.vault_key_file_path}"
  }
}

output "key_file_path" {
  value       = var.vault_key_file_path
  description = "Path to the generated Service Account key file."
}


resource "google_kms_key_ring" "vault_key_ring" {
  name       = "vault"
  location   = var.region
  depends_on = [google_project_iam_member.storage_service_account_kms]
}

resource "google_kms_crypto_key" "vault_crypto_key" {
  name            = "vault-unsealer"
  key_ring        = google_kms_key_ring.vault_key_ring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true # Protects the key from accidental deletion
  }
}

resource "google_storage_bucket" "vault" {
  name          = "bhamm-lab-vault"
  location      = var.bucket_location
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.vault_crypto_key.id
  }

  lifecycle_rule {
    condition {
      age = 120
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "vault_storage_admin" {
  bucket = google_storage_bucket.vault.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vault_sa.email}"
}

resource "google_project_iam_member" "vault_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.vault_sa.email}"
}
