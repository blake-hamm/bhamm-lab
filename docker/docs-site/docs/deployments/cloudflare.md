# Cloudflare

This manages my Cloudflare resources, including R2 storage buckets and Zero Trust tunnels for secure connectivity.

## Resources Managed

### R2 Storage Bucket
- **Minio Mirror Bucket**: Creates an R2 bucket named `seaweedfs` which is a mirror of TrueNas minio bucket
- **Location**: Deployed in `wnam` (West North America) region
- **Storage Class**: Uses Standard storage class for cost-effective object storage

### Zero Trust Tunnel
- **Static Site Tunnel**: Creates a Cloudflare Zero Trust tunnel named `bhamm-lab-site`
- **Secure Connectivity**: Provides encrypted tunnel access to internal resources
- **Secret Management**: Uses SOPS to securely manage tunnel secrets from Vault

## Configuration

### Required Providers
- **Cloudflare Provider**: Version ~> 5 for Cloudflare API access
- **SOPS Provider**: Version 1.2.0 for secrets management

### Required Variables
- `cloudflare_api_token`: API token for Cloudflare authentication
- `cloudflare_account_id`: Cloudflare account ID for resource scoping

### Optional Variables with Defaults
- `truenas_bucket_name`: `seaweedfs` (TrueNAS storage bucket name)
- `truenas_bucket_location`: `wnam` (R2 bucket location)
- `truenas_bucket_storage_class`: `Standard` (R2 storage class)
- `tunnel_name`: `bhamm-lab-site` (Zero Trust tunnel name)

### Secrets Management
- **Source**: Retrieves secrets from `../../secrets.enc.json`
- **Vault Integration**: Accesses `vault_secrets.external.cloudflare.tunnel_secret`
- **Security**: Uses SOPS for encrypted secret management

## Usage

```bash
# Initialize Terraform
tofu -chdir=tofu/cloudflare init

# Review changes
tofu -chdir=tofu/cloudflare plan

# Apply changes (auto-approve for automation)
tofu -chdir=tofu/cloudflare apply -auto-approve
```

## Output

After successful deployment:
- **R2 Bucket**: `seaweedfs` bucket will be available in Cloudflare R2
- **Zero Trust Tunnel**: `bhamm-lab-site` tunnel will be configured for secure access
- **DNS Integration**: Can be used with Cloudflare DNS for custom domain routing

## Use Cases

### TrueNAS (minio) Offsite Storage
- Object storage to mirror local TrueNas (minio)
- Cost-effective alternative to GCP

### Zero Trust Tunnels
- Secure access to select internal services without exposing public IPs
- Encrypted connectivity for static sites and internal applications
- Enhanced security with Cloudflare's Zero Trust security model