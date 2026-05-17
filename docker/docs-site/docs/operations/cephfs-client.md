# CephFS Client Mounts

Mount CephFS directories on external machines (e.g. the Framework laptop) using the **Linux kernel CephFS client**.

## Overview

| Property | Value |
|----------|-------|
| Host | `framework` |
| Mount point | `/mnt/bhamm` |
| Ceph client | `client.bhamm` |
| Access | Read-write, restricted to `/bhamm` |
| Mount mode | **On-demand automount** (systemd) |
| Idle timeout | 5 minutes |
| Tool | `mount.ceph` (kernel client) |

## Architecture

```
┌─────────────┐     autofs ──► mount.ceph     ┌─────────────────────────────┐
│  Framework  │ ◄───────────────────────────► │  Proxmox Ceph Cluster       │
│  /mnt/bhamm │  mounts on first access       │  cephfs_data pool           │
└─────────────┘  unmounts after 5 min idle    │  /bhamm/...                 │
                                               └─────────────────────────────┘
```

The Framework laptop connects directly to Ceph mons (10.0.20.11/12/13) on the local network. No VPN required when at home.

### On-Demand Behavior

The mount uses **systemd automount** — it is not connected to Ceph at boot. Instead:

1. **First access** (`ls /mnt/bhamm`, file manager, etc.) triggers the mount
2. The kernel Ceph client connects to the cluster and mounts the filesystem
3. After **5 minutes of idle** time, systemd automatically unmounts
4. Before **sleep/hibernate**, the mount is cleanly stopped to prevent stale sessions
5. Next access after resume triggers a **fresh mount**

The kernel client is more stable than FUSE for intermittent use — no userspace daemon to crash or hang. The first access after boot or resume has a ~1–2 second delay while the connection establishes.

## Backend Setup

Run on any Ceph mon (e.g. Proxmox node):

```bash
# Mount CephFS root as admin to create directories
sudo mount.ceph 10.0.20.11:6789:/ /tmp/cephfs-root -o name=admin,secret=$(sudo ceph auth get-key client.admin)
sudo mkdir -p /tmp/cephfs-root/bhamm/bhamm-sports
sudo umount /tmp/cephfs-root

# Create a restricted client key scoped to /bhamm
ceph auth get-or-create client.bhamm \
  mon 'allow r' \
  osd 'allow rw pool=cephfs_data' \
  mds 'allow rw path=/bhamm' \
  mgr 'allow r'

# Export the keyring for use on the client
ceph auth get client.bhamm -o /tmp/cephfs_client_keyring
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

Systemd units handle the mount:
- `mnt-bhamm.automount` — creates the on-demand trigger
- `mnt-bhamm.mount` — performs the actual kernel mount when accessed
- `cephfs-bhamm-sleep.service` — cleanly unmounts before sleep/hibernate

## Operations

### Check mount status

```bash
# Is the automount trigger active?
systemctl status mnt-bhamm.automount

# Is the filesystem currently mounted?
systemctl status mnt-bhamm.mount
mount | grep bhamm

# Access triggers mount (first call may take 1–2s)
ls -la /mnt/bhamm
```

### Force mount/unmount manually

```bash
# Mount now (normally triggered automatically on access)
sudo systemctl start mnt-bhamm.mount

# Unmount now (normally happens automatically after idle)
sudo systemctl stop mnt-bhamm.mount
```

### Manual mount (debugging)

```bash
sudo mount -t ceph \
  10.0.20.11:6789,10.0.20.12:6789,10.0.20.13:6789:/bhamm \
  /mnt/bhamm \
  -o name=bhamm,conf=/run/secrets/cephfs_conf,secretfile=/run/ceph/bhamm.key,_netdev
```

The kernel client needs the **raw key** (not the full keyring). The activation script extracts it from the sops secret to `/run/ceph/bhamm.key` at boot time.

## Data Storage

CephFS stores file data in the `cephfs_data` pool alongside all other CephFS content. The `client.bhamm` key is restricted to `/bhamm` so the client cannot access other CephFS directories.

There is no separate volume or pool for the sports data — it's namespace isolation within the shared filesystem. If dedicated pools are needed later (e.g. for performance isolation), create a second CephFS filesystem with its own data pool.
