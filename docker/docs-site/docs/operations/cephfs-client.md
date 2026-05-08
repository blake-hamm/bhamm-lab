# CephFS Client Mounts

Mount CephFS directories on external machines (e.g. the Framework laptop) using `ceph-fuse`.

## Overview

| Property | Value |
|----------|-------|
| Host | `framework` |
| Mount point | `/mnt/bhamm-sports` |
| Ceph client | `client.bhamm-sports` |
| Access | Read-write, restricted to `/volumes/_nogroup/bhamm-sports` subvolume |
| Tool | `ceph-fuse` (via `mount.fuse.ceph`) |

## Architecture

```
┌─────────────┐     ceph-fuse      ┌─────────────────────────────┐
│  Framework  │ ◄────────────────► │  Proxmox Ceph Cluster       │
│  /mnt/...   │   (S3 + CephFS)    │  cephfs_data pool           │
└─────────────┘                    │  /volumes/_nogroup/...      │
                                   └─────────────────────────────┘
```

The Framework laptop connects directly to Ceph mons (10.0.20.11/12/13) on the local network. No VPN required when at home.

## Backend Setup

Run on any Ceph mon (e.g. Proxmox node):

```bash
# Create a subvolume (directory with quota/namespace isolation)
ceph fs subvolume create cephfs bhamm-sports

# Get the actual path
ceph fs subvolume getpath cephfs bhamm-sports
# → /volumes/_nogroup/bhamm-sports

# Create a restricted client key
ceph auth get-or-create client.bhamm-sports \
  mon 'allow r' \
  osd 'allow rw pool=cephfs_data' \
  mds 'allow rw path=/volumes/_nogroup/bhamm-sports' \
  mgr 'allow r'

# Export the keyring for use on the client
ceph auth get client.bhamm-sports -o /tmp/cephfs_client_keyring
```

## NixOS Configuration

The client config lives in `nix/modules/services/cephfs.nix`.

### Secrets

Add to `secrets.enc.json` (via sops):

| Secret | Path in secrets.enc.json |
|--------|--------------------------|
| Ceph config | `vault_secrets/core/cephfs/ceph_conf` |
| Client keyring | `vault_secrets/core/cephfs/client_keyring` |

### Enable on a host

```nix
# nix/hosts/framework/default.nix
{
  cfg.cephfs.enable = true;
}
```

### Rebuild

```bash
sudo nixos-rebuild switch --flake .#framework
```

The `cephfs-bhamm-sports.service` systemd unit handles the mount.

## Operations

### Check mount status

```bash
systemctl status cephfs-bhamm-sports.service
mount | grep bhamm-sports
ls -la /mnt/bhamm-sports
```

### Manual mount (debugging)

```bash
sudo /nix/store/...-ceph-client/bin/mount.fuse.ceph \
  -o ceph.id=bhamm-sports,\
      ceph.conf=/run/secrets/cephfs_conf,\
      ceph.keyring=/run/secrets/cephfs_keyring,\
      ceph.client-mountpoint=/bhamm-sports,\
      _netdev,defaults,nonempty \
  -- none /mnt/bhamm-sports
```

**Note:** The `--` separator is required because `mount.fuse.ceph` uses argparse and treats `none` as an optional argument without it.

### Unmount

```bash
sudo umount /mnt/bhamm-sports
```

## Data Storage

CephFS stores file data in the `cephfs_data` pool alongside all other CephFS content. The `client.bhamm-sports` key is restricted to a specific path (`/volumes/_nogroup/bhamm-sports`) so the client cannot access other CephFS directories.

There is no separate volume or pool for the sports data — it's namespace isolation within the shared filesystem. If dedicated pools are needed later (e.g. for performance isolation), create a second CephFS filesystem with its own data pool.
