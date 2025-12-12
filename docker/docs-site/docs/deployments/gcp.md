# GCP

This manages my GCP resources, primarily focused on Cloud KMS and service accounts for SOPS (Secrets OPerations) encryption and decryption.

## Resources Managed

### Cloud KMS Setup
- **KMS Key Ring**: Creates a key ring in `us-central1` region for SOPS operations
- **Crypto Key**: Generates a rotation key that rotates every 90 days for SOPS encryption
- **Service Account**: Creates a dedicated service account (`gcp-sops-decrypt`) for decrypting secrets
- **IAM Permissions**: Grants necessary KMS permissions to storage service accounts and the SOPS service account

### Service Account Management
- **SOPS Decrypt Service Account**: Dedicated service account with KMS decrypt permissions
- **Key Export**: Automatically exports the private key to `./result/gcp-sops-sa.json` for local use

## Configuration

### Project Details
- **Project ID**: `deep-contact-445917-i9`
- **Default Region**: `us-central1`

### Required Providers
- **Google Cloud Provider**: Version 4.85.0
- **Vault Provider**: Version 3.25.0 (commented out)

## Usage

```bash
# Initialize Terraform
tofu -chdir=tofu/gcp init

# Review changes
tofu -chdir=tofu/gcp plan

# Apply changes (auto-approve for automation)
tofu -chdir=tofu/gcp apply -auto-approve
```

## Output

After successful deployment, the service account key will be available at:
```
./result/gcp-sops-sa.json
```

This key can be used with SOPS to decrypt secrets stored in this GCP project.