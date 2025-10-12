resource "google_project_iam_member" "storage_service_account_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
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
