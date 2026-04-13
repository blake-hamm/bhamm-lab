output "bucket_name" {
  description = "Name of the B2 bucket"
  value       = b2_bucket.ceph_rgw.bucket_name
}

output "bucket_id" {
  description = "ID of the B2 bucket"
  value       = b2_bucket.ceph_rgw.id
}

output "s3_endpoint" {
  description = "B2 S3-compatible endpoint"
  value       = "https://s3.us-west-002.backblazeb2.com"
}

output "application_key_id" {
  description = "ID of the application key"
  value       = b2_application_key.ceph_rgw.application_key_id
}

output "application_key" {
  description = "The application key secret"
  value       = b2_application_key.ceph_rgw.application_key
  sensitive   = true
}
