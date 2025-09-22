resource "google_project_iam_member" "storage_service_account_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# kms, sa and bucket for k8up
resource "google_kms_key_ring" "k8up_key_ring" {
  name       = "k8up-key-ring"
  location   = var.region
  depends_on = [google_project_iam_member.storage_service_account_kms]
}

resource "google_kms_crypto_key" "k8up_crypto_key" {
  name            = "k8up-crypto-key"
  key_ring        = google_kms_key_ring.k8up_key_ring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_storage_bucket" "k8up" {
  name          = "bhamm-lab-k8up"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.k8up_crypto_key.id
  }
}

resource "google_service_account" "k8up" {
  account_id   = var.k8up_service_account_id
  display_name = "k8up SA"
}

resource "google_project_iam_member" "k8up_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.k8up.email}"
}

resource "google_storage_bucket_iam_member" "k8up_storage_admin" {
  bucket = google_storage_bucket.k8up.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.k8up.email}"
}

resource "google_service_account_key" "k8up_key" {
  service_account_id = google_service_account.k8up.name

  provisioner "local-exec" {
    command = "echo '${self.private_key}' | base64 --decode > ${var.k8up_key_file_path}"
  }
}

resource "google_storage_hmac_key" "k8up_hmac" {
  service_account_email = google_service_account.k8up.email

  # Save credentials to a local JSON file for k8up
  provisioner "local-exec" {
    command = <<-EOT
      echo '{
        "access_id": "${self.access_id}",
        "secret": "${self.secret}"
      }' > ${var.k8up_hmac_credentials_path}
    EOT
  }
}

# Store credentials in Vault
# resource "vault_generic_secret" "velero_creds" {
#   path = "secret/core/argo-workflows"

#   data_json = jsonencode({
#     "gcp_credentials.json" = base64decode(google_service_account_key.velero_key.private_key),
#     "bucket_name"          = google_storage_bucket.backup.name,
#     "project_id"           = var.project_id
#   })
# }

# kms and sa for sops
resource "google_kms_key_ring" "sops_key_ring" {
  name       = "sops-key-ring"
  location   = var.region
  depends_on = [google_project_iam_member.storage_service_account_kms]
}

resource "google_kms_crypto_key" "sops_crypto_key" {
  name            = "sops-key"
  key_ring        = google_kms_key_ring.sops_key_ring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "sops_sa" {
  account_id   = "gcp-sops-decrypt"
  display_name = "SOPS Decrypt Key"
}

resource "google_kms_crypto_key_iam_member" "sops_key_access" {
  crypto_key_id = google_kms_crypto_key.sops_crypto_key.id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${google_service_account.sops_sa.email}"
}

resource "google_service_account_key" "sops_sa_key" {
  service_account_id = google_service_account.sops_sa.name

  provisioner "local-exec" {
    command = "echo '${self.private_key}' | base64 --decode > ${var.sops_key_file_path}"
  }
}
