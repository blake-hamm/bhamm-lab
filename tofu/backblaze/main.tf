resource "b2_bucket" "ceph_rgw" {
  bucket_name = var.bucket_name
  bucket_type = "allPrivate"

  default_server_side_encryption {
    mode      = "SSE-B2"
    algorithm = "AES256"
  }

  # rclone sync deletes are B2 "hide" operations and restic rewrites old packs,
  # so without expiry every upstream delete accumulates as a billed hidden
  # version forever. Hidden versions purge 30 days after hiding (keeps a
  # 30-day offsite oops-window); interrupted large uploads cancel after 1 day.
  # days_from_uploading_to_hiding is deliberately NOT set: it would hide
  # current versions too. B2 applies lifecycle rules once per day.
  # backblaze is on the tofu-ci plan allow-list (ENABLED_STACKS), so edits here
  # get a credentialed `tofu plan` against real state on every push.
  lifecycle_rules {
    file_name_prefix                                       = ""
    days_from_hiding_to_deleting                           = 30
    days_from_starting_to_canceling_unfinished_large_files = 1
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
