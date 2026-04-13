resource "b2_bucket" "ceph_rgw" {
  bucket_name = var.bucket_name
  bucket_type = "allPrivate"

  default_server_side_encryption {
    mode      = "SSE-B2"
    algorithm = "AES256"
  }
}

resource "b2_application_key" "ceph_rgw" {
  key_name   = var.key_name
  bucket_ids = [b2_bucket.ceph_rgw.id]
  capabilities = [
    "listBuckets",
    "readBuckets",
    "writeBuckets",
    "readFiles",
    "writeFiles",
    "deleteFiles",
    "listFiles",
    "readBucketEncryption",
    "writeBucketEncryption"
  ]
}

resource "local_file" "b2_creds" {
  content         = <<-EOT
    B2_APPLICATION_KEY_ID=${b2_application_key.ceph_rgw.application_key_id}
    B2_APPLICATION_KEY=${b2_application_key.ceph_rgw.application_key}
    B2_BUCKET_NAME=${b2_bucket.ceph_rgw.bucket_name}
    B2_ENDPOINT=https://s3.us-west-002.backblazeb2.com
  EOT
  filename        = "${path.module}/result/b2-creds.txt"
  file_permission = "0600"
}
