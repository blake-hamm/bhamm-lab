variable "b2_application_key_id" {
  description = "Backblaze B2 application key ID"
  type        = string
}

variable "b2_application_key" {
  description = "Backblaze B2 application key"
  type        = string
  sensitive   = true
}

variable "bucket_name" {
  description = "Name of the B2 bucket for Ceph RGW backups"
  type        = string
  default     = "bhamm-lab-ceph-rgw"
}

variable "key_name" {
  description = "Name of the application key for bucket access"
  type        = string
  default     = "ceph-rgw-backup-key"
}
