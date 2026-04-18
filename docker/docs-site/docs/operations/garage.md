# Garage Object Storage

Garage is a lightweight, self-hosted S3-compatible object storage service running on a NixOS VM (`garage`, `10.0.20.21`) in the Proxmox cluster. It replaces TrueNAS/MinIO as the backup target for the green cluster.

## Architecture

- **Host:** `garage` (`10.0.20.21`, VLAN 20)
- **Node:** Proxmox `japan`
- **Storage:** 3x physical SSDs via HBA PCIe passthrough
  - 2x PNY CS900 2TB (`disk1`, `disk2`)
  - 1x Crucial CT1000BX500SSD1 1TB (`disk3`)
- **Replication Factor:** 1 (single-node cluster, no redundancy)
- **Network:** S3 API on port 3900, RPC on localhost:3901, Admin on localhost:3903

## Files

| File | Purpose |
|------|---------|
| `nix/hosts/garage/default.nix` | Main host config (imports, networking, GRUB, fstrim) |
| `nix/hosts/garage/garage.nix` | Garage service, secrets, mounts, firewall |
| `nix/hosts/garage/disko.nix` | **Reference only** — disk layout documentation |
| `nix/hosts/garage/hardware-configuration.nix` | Generated hardware config (boot disk UUIDs) |
| `tofu/proxmox/garage/` | OpenTofu VM definition |

## Deployment (Full Rebuild)

These steps assume a completely fresh VM or a full `tofu destroy && tofu apply`.

### 1. Ensure VM age key is in SOPS

Every VM rebuild generates a new SSH host key. The garage VM's age key (derived from `/etc/ssh/ssh_host_ed25519_key`) must be authorized in `.sops.yaml`.

Get the new key:

```bash
ssh-keyscan -p 4185 -t ed25519 10.0.20.21 | nix run nixpkgs#ssh-to-age
```

Update `.sops.yaml` with the new `&garage` age key (and the GPG fingerprint from `/etc/ssh/ssh_host_rsa_key` if needed).

Re-encrypt secrets:

```bash
sops updatekeys secrets.enc.json
```

### 2. Deploy NixOS config

```bash
cd ~/repos/bhamm-lab
colmena apply --on garage --impure
```

This deploys the full Garage config, including:
- `services.garage` with 3 data disks
- `sops-nix` secrets (`rpc_secret`, `admin_token`)
- `systemd` automount units for `/mnt/garage/disk{1,2,3}`
- Firewall rule on TCP 3900

### 3. Partition and format the data disks (One-Time)

SSH into the VM and create GPT partitions + XFS filesystems:

```bash
ssh -p 4185 bhamm@10.0.20.21

# Create GPT partitions
sudo parted -s /dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009C8 mklabel gpt mkpart data xfs 0% 100%
sudo parted -s /dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009CB mklabel gpt mkpart data xfs 0% 100%
sudo parted -s /dev/disk/by-id/ata-CT1000BX500SSD1_2308E6B0E700 mklabel gpt mkpart data xfs 0% 100%

# Format as XFS
sudo mkfs.xfs -f /dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009C8-part1
sudo mkfs.xfs -f /dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009CB-part1
sudo mkfs.xfs -f /dev/disk/by-id/ata-CT1000BX500SSD1_2308E6B0E700-part1

# Create mountpoint directories
sudo mkdir -p /mnt/garage/disk{1,2,3}
```

**Why not disko?** We intentionally do **not** use `disko.nix` for the data disks. Disko generates `fileSystems.*` entries that systemd mounts at boot. If disks aren't formatted yet, `local-fs.target` hangs indefinitely, and without Proxmox console access the VM is unrecoverable. The automount approach (`noauto` + `x-systemd.automount`) lets the system boot normally and mount disks lazily on first access.

### 4. Fix data directory permissions

The `garage` user (created by the NixOS config) needs ownership of the mountpoints:

```bash
sudo chown -R garage:garage /mnt/garage/disk*
```

### 5. Verify Garage is running

```bash
# Trigger the automounts
ls /mnt/garage/disk1 /mnt/garage/disk2 /mnt/garage/disk3

# Check mounts
mount | grep garage

# Check service status
sudo systemctl status garage

# Get node ID
sudo -u garage garage node id
```

Expected output: a 64-character hex node ID.

### 6. Configure Garage cluster layout

Assign the node to the `japan` zone:

```bash
NODE_ID=$(sudo -u garage garage node id | head -1)

# Stage the layout change
sudo -u garage garage layout assign -z japan -c 5TB $NODE_ID

# Review staged changes
sudo -u garage garage layout show

# Apply with version number (replace 1 with the version shown)
sudo -u garage garage layout apply --version 1
```

### 7. Create bucket and access key

```bash
# Create the bucket
sudo -u garage garage bucket create ceph-rgw

# Create an access key
sudo -u garage garage key create garage-key
```

**Save the output.** You need the `Key ID` and `Secret key` for the next step.

### 8. Grant key access to bucket

```bash
sudo -u garage garage bucket allow ceph-rgw --key garage-key --read --write
```

### 9. Update secrets.enc.json

Add the generated S3 credentials to `vault_secrets.core.garage`:

```json
"garage": {
  "rpc_secret": "<hex-output>",
  "admin_token": "<base64-output>",
  "s3_access_key": "<Key ID from garage key create>",
  "s3_secret_key": "<Secret key from garage key create>"
}
```

Re-encrypt and commit:

```bash
sops -e -i secrets.enc.json
git add secrets.enc.json .sops.yaml nix/hosts/garage/
git commit -m "Update garage S3 credentials and config"
```

## Post-Deploy Verification

```bash
# Service health
ssh -p 4185 bhamm@10.0.20.21
sudo systemctl status garage

# Node status
sudo -u garage garage status

# Bucket info
sudo -u garage garage bucket info ceph-rgw

# Check mounts
df -h | grep garage
lsblk
```

## Troubleshooting

### "Permission denied" on startup

The `garage` user cannot read the data directories. Fix ownership:

```bash
sudo chown -R garage:garage /mnt/garage/disk*
```

### "File is world-readable" error

Garage enforces `0600` permissions on secret files. The NixOS config handles this via `sops.secrets.*.mode = "0600"` and `owner = "garage"`.

### "Layout not ready" when creating buckets

You must assign the node to a zone and apply the layout **before** creating buckets or keys. See Step 6.

### SOPS decryption fails after VM rebuild

The VM's SSH host key changes on rebuild. The new age/GPG fingerprint must be added to `.sops.yaml` and secrets re-encrypted with `sops updatekeys secrets.enc.json`.

### VM stuck in emergency mode (historical)

This happened when `disko.nix` was imported and generated boot-time mount entries. The fix was to remove disko and use `noauto` + `x-systemd.automount` mounts. See `nix/hosts/garage/garage.nix` for the current mount configuration.

## Maintenance

### Restart Garage

```bash
ssh -p 4185 bhamm@10.0.20.21
sudo systemctl restart garage
```

### Admin API (localhost only)

Tunnel through SSH for admin operations:

```bash
ssh -p 4185 -L 3903:localhost:3903 bhamm@10.0.20.21
# Then access http://localhost:3903
```

### TRIM

`services.fstrim.enable = true` is enabled in the host config. Consumer SSDs benefit from periodic TRIM for longevity.

## Key Design Decisions

1. **No disko for data disks:** Boot-time mounts from unformatted disks cause irrecoverable hangs without console access.
2. **Dedicated `garage` user:** Replaces `DynamicUser=true` so we can manage directory ownership and run CLI commands as the service user.
3. **Single-node, replication=1:** No redundancy — this is a backup target, not primary storage. Ceph RGW remains the primary S3 endpoint.
4. **XFS on bare partitions:** Simple, robust filesystem for object storage backends.
5. **HBA passthrough:** Direct disk access via PCIe passthrough avoids Proxmox virtual disk overhead.
