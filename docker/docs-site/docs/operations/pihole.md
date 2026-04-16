# Pi-hole

## Overview

Pi-hole serves as a DNS server for ad-blocking and metrics on all VLAN's, except for the 'public' (wife's) VLAN. It runs on two Orange Pi Zero3 devices with automatic failover via Keepalived (VRRP) using floating VIP `10.0.9.2`.

## Hosts

| Host | IP | Role | Admin URL |
|------|-----|------|-----------|
| orangepi-zero3 | 10.0.9.3 | Primary (MASTER) | https://10.0.9.3/admin |
| orangepi-zero3-backup | 10.0.9.4 | Backup (BACKUP) | https://10.0.9.4/admin |
| VIP | 10.0.9.2 | Active DNS | https://10.0.9.2/admin |

## Configuration

The Pi-hole instances are configured via `nix/modules/services/pihole.nix`.

### Services

| Service | Description | Ports |
|---------|-------------|-------|
| `pihole-ftl` | DNS server (FTLDNS) | 53/tcp, 53/udp |
| `pihole-web` | Web administration interface | 80/tcp, 443/tcp |
| `keepalived` | VRRP daemon for VIP failover | N/A |

### DNS Settings

| Setting | Value |
|---------|-------|
| **Upstream DNS** | `10.0.9.1` (unbound service on OPNsense with override for *.bhamm-lab.com) |
| **Listening Mode** | ALL (responds to queries from all origins) |
| **DHCP** | Disabled |


## Infrastructure DNS Integration

Pi-hole (`10.0.9.2`) is configured as the primary DNS server across all infrastructure components.

### OPNsense Firewall Rules

All VLANs have firewall rules allowing DNS traffic to `10.0.9.2:53`. Configuration is managed via `ansible/roles/opnsense/tasks/rules.yml`.

### Proxmox Hosts

All Proxmox hosts use `10.0.9.2` as their DNS server via network templates. Configuration is defined in `ansible/inventory/group_vars/proxmox.yml`.

### Talos Kubernetes Nodes

All Talos masters and workers use `["10.0.9.2"]` as nameservers via the `dns_servers` variable. Configuration is defined in `tofu/proxmox/talos/variables.tf`.

## Operations

### Accessing the Web Interface

The Pi-hole admin interface is available at any of the following URLs:

```
https://10.0.9.2      # VIP (always points to active node)
https://10.0.9.3      # Primary node
https://10.0.9.4      # Backup node
```

### Updating Pi-hole Configuration

To apply configuration changes to both Pi-hole instances, run:

```bash
# Deploy both hosts
colmena apply --on @sbc --impure

# Or deploy individually
colmena apply --on orangepi-zero3 --impure
colmena apply --on orangepi-zero3-backup --impure
```

### Failover Testing

```bash
# Check VRRP status
ssh orangepi-zero3 systemctl status keepalived
ssh orangepi-zero3-backup systemctl status keepalived

# Check which host has VIP
ssh orangepi-zero3 ip addr show end0 | grep 10.0.9.2
ssh orangepi-zero3-backup ip addr show end0 | grep 10.0.9.2

# Test failover by stopping pihole on primary
ssh orangepi-zero3 sudo systemctl stop pihole-ftl
# VIP should move to backup within 2 seconds

# Restore primary
ssh orangepi-zero3 sudo systemctl start pihole-ftl
# VIP should return to primary after ~5 seconds
```

### Maintenance

**Graceful failover for maintenance:**
```bash
# Stop keepalived on primary to trigger failover
ssh orangepi-zero3 sudo systemctl stop keepalived
# VIP moves to backup automatically

# Perform maintenance, then restore
ssh orangepi-zero3 sudo systemctl start keepalived
```

**Updating blocklists:**
Since Pi-hole sync is not configured, update lists manually or via script on both hosts.

## NUT UPS Servers

Both Orange Pi Zero3 devices run independent NUT (Network UPS Tools) servers to monitor their attached CyberPower UPS units and trigger graceful shutdown on power loss.

### UPS Details

| Host | UPS Model | Runtime |
|------|-----------|---------|
| orangepi-zero3 | CyberPower OR1500LCDRT2U | ~24 minutes at current load |
| orangepi-zero3-backup | CyberPower OR1500LCDRT2U | ~24 minutes at current load |

### NUT Services

| Service | Description |
|---------|-------------|
| `upsdrv` | USB HID UPS driver (`usbhid-ups`) |
| `upsd` | NUT server exposing UPS data |
| `upsmon` | Monitor triggering shutdown when battery low |

### Operations

```bash
# Check UPS status
ssh orangepi-zero3 upsc cyberpower@localhost
ssh orangepi-zero3-backup upsc cyberpower@localhost

# Run battery self-test
upscmd -u nut-admin -p $(ssh orangepi-zero3 cat /run/secrets/nut_password) cyberpower test.battery.start.quick
```

### Configuration

NUT is configured via `nix/modules/services/nut.nix` with shared settings in `nix/profiles/orangepi-pihole.nix`. Password is managed via SOPS (`nix/secrets.yaml`).
