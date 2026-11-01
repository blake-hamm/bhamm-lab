# Cloudflare

This manages my Cloudflare resources, including R2 storage buckets (standby) and Zero Trust tunnels for secure connectivity.

## Resources Managed

### R2 Storage Bucket
- **Ceph RGW Standby Mirror**: Creates an R2 bucket named `ceph-rgw` which is a standby mirror of Ceph RGW data
- **Location**: Deployed in `wnam` (West North America) region
- **Storage Class**: Uses Standard storage class
- **Role**: Secondary/fallback restore source — Backblaze B2 is the primary offsite tier

### Zero Trust Tunnel
- **Static Site Tunnel**: Creates a Cloudflare Zero Trust tunnel named `bhamm-lab-site`
- **Secure Connectivity**: Provides encrypted tunnel access to internal resources
- **Secret Management**: `tunnel_secret` is a required variable sourced from Vault `external/cloudflare`

## Configuration

### Required Providers
- **Cloudflare Provider**: Version ~> 5 for Cloudflare API access

### Required Variables
- `cloudflare_api_token`: API token for Cloudflare authentication
- `cloudflare_account_id`: Cloudflare account ID for resource scoping
- `tunnel_secret`: Base64 Cloudflare tunnel secret (required; a missing value must hard-error, never silently rotate the live tunnel secret)

All three are sourced from Vault `external/cloudflare` (keys `terraform-token`, `account-id`, `tunnel_secret`).

### Secrets Management
- **Source**: Vault kv path `external/cloudflare` (synced from SOPS by the sops->vault job)
- **Passing**: `-var` flags or `TF_VAR_*` env; CI passes `-var` per plan so values never linger in job env

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
- **R2 Bucket**: `ceph-rgw` bucket will be available in Cloudflare R2 as standby backup
- **Zero Trust Tunnel**: `bhamm-lab-site` tunnel will be configured for secure access
- **DNS Integration**: Can be used with Cloudflare DNS for custom domain routing

## Use Cases

### Offsite Standby Storage
- Object storage mirror of Ceph RGW data for disaster recovery
- Restore path: R2 → Garage → Ceph RGW (via Argo workflow)
- Backblaze B2 serves as the primary offsite tier

### Zero Trust Tunnels
- Secure access to select internal services without exposing public IPs
- Encrypted connectivity for static sites and internal applications
- Enhanced security with Cloudflare's Zero Trust security model
