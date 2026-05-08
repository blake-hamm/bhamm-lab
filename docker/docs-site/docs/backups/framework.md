# Framework Laptop Backups

Encrypted restic backups of the Framework laptop's home directory to Ceph RGW.

## Overview

| Property | Value |
|----------|-------|
| Host | `framework` |
| Tool | Restic |
| Target | Ceph RGW (S3-compatible) |
| Repository | `s3:https://rgw.bhamm-lab.com/framework-backup` |
| Schedule | Daily at 04:00 (persistent, 30min random delay) |
| Retention | Last 5, daily 2, weekly 1, monthly 1, yearly 1 |

## NixOS Configuration

Enabled in `nix/hosts/framework/default.nix`:

```nix
{
  cfg.backups.enable = true;
  cfg.backups.target = "rgw";
}
```

The `rgw` target is defined in `nix/modules/services/backups.nix`.

## Secrets

Secrets live in `secrets.enc.json` (sops-encrypted):

| Secret | Path in secrets.enc.json | Purpose |
|--------|--------------------------|---------|
| RGW access key | `init/ceph/ceph-external-secret/s3_access_key` | S3 auth |
| RGW secret key | `init/ceph/ceph-external-secret/s3_secret_key` | S3 auth |
| Restic password | `vault_secrets/core/backups/restic_password` | Repo encryption |

## Exclusions

The following are excluded from backup:

- `~/.cache`
- `~/Downloads`
- `~/.local/share/Steam/steamapps/common`
- `~/.local/share/docker`
- `~/.conda`
- `~/backups`
- `/mnt/bhamm-sports` (CephFS mount — data already on redundant ceph storage)

## Operations

### Check backup status

```bash
sudo systemctl status restic-backups-framework.service
sudo systemctl status restic-backups-framework.timer
journalctl -u restic-backups-framework.service -f
```

### List snapshots

```bash
# The service environment file is needed for AWS credentials
source <(sudo cat /run/secrets/restic-rgw-env)
export RESTIC_PASSWORD=$(sudo cat /run/secrets/restic_password)
export RESTIC_REPOSITORY=s3:https://rgw.bhamm-lab.com/framework-backup

restic snapshots
```

### Manual restore

```bash
source <(sudo cat /run/secrets/restic-rgw-env)
export RESTIC_PASSWORD=$(sudo cat /run/secrets/restic_password)
export RESTIC_REPOSITORY=s3:https://rgw.bhamm-lab.com/framework-backup

# List snapshots
restic snapshots

# Restore latest to /tmp/restore
restic restore latest --target /tmp/restore

# Restore specific snapshot
restic restore <snapshot-id> --target /tmp/restore --include /home/bhamm/Documents
```

### Check repository integrity

```bash
source <(sudo cat /run/secrets/restic-rgw-env)
export RESTIC_PASSWORD=$(sudo cat /run/secrets/restic_password)
export RESTIC_REPOSITORY=s3:https://rgw.bhamm-lab.com/framework-backup

restic check --read-data-subset=10%
```

The timer runs this automatically after each backup.

## Troubleshooting

**Hung backup**

If the service shows `S (sleeping)` with no TCP connections for hours, the network connection may have stalled. Kill and restart:

```bash
sudo systemctl stop restic-backups-framework.service
sudo systemctl start restic-backups-framework.service
```

Restic is resumable — it will pick up where it left off.

**Progress output**

Progress logs every 20 seconds in the journal via `RESTIC_PROGRESS_FPS=0.05`.
