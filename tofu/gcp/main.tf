resource "google_project_iam_member" "storage_service_account_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# kms, sa and bucket for velero
resource "google_kms_key_ring" "velero_key_ring" {
  name       = "velero-key-ring"
  location   = var.region
  depends_on = [google_project_iam_member.storage_service_account_kms]
}

resource "google_kms_crypto_key" "velero_crypto_key" {
  name            = "velero-crypto-key"
  key_ring        = google_kms_key_ring.velero_key_ring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true # Protects the key from accidental deletion
  }
}

resource "google_storage_bucket" "velero" {
  name          = "bhamm-lab-velero"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.velero_crypto_key.id
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_service_account" "velero" {
  account_id   = var.velero_service_account_id
  display_name = "Velero SA"
}

resource "google_project_iam_member" "velero_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.velero.email}"
}

resource "google_storage_bucket_iam_member" "velero_storage_admin" {
  bucket = google_storage_bucket.velero.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.velero.email}"
}

resource "google_service_account_key" "velero_key" {
  service_account_id = google_service_account.velero.name

  provisioner "local-exec" {
    command = "echo '${self.private_key}' | base64 --decode > ${var.velero_key_file_path}"
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

# kms, sa and bucket for vault unseal
resource "google_service_account" "vault_sa" {
  account_id   = var.vault_service_account_id
  display_name = "Vault Auto Unseal SA"
}

resource "google_service_account_key" "vault_sa_key" {
  service_account_id = google_service_account.vault_sa.name

  provisioner "local-exec" {
    command = "echo '${self.private_key}' | base64 --decode > ${var.vault_key_file_path}"
  }
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

resource "google_kms_crypto_key_iam_member" "vault_sa_kms_access" {
  crypto_key_id = google_kms_crypto_key.vault_crypto_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.vault_sa.email}"
}

resource "google_kms_key_ring_iam_member" "vault_sa_kms_viewer" {
  key_ring_id = google_kms_key_ring.vault_key_ring.id
  role        = "roles/cloudkms.viewer"
  member      = "serviceAccount:${google_service_account.vault_sa.email}"
}

resource "google_storage_bucket" "vault" {
  name          = "bhamm-lab-vault"
  location      = var.region
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
    prevent_destroy = true # Protects the key from accidental deletion
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
