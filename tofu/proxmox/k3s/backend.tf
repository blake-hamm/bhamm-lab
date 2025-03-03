terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "k3s/terraform.state"
    endpoints = {
      s3 = "https://minio-api.bhamm-lab.com"
    }
    region                      = "main"
    skip_requesting_account_id  = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
  }
}