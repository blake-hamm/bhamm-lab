# Pi-hole

## Overview

Pi-hole serves as a DNS server for ad-blocking and metrics on all VLAN's, except for the 'public' (wife's) VLAN. It runs on an Orange Pi Zero3 with static IP `10.0.9.2`.

## Configuration

The Pi-hole instance is configured via `nix/modules/services/pihole.nix`.

### Services

| Service | Description | Ports |
|---------|-------------|-------|
| `pihole-ftl` | DNS server (FTLDNS) | 53/tcp, 53/udp |
| `pihole-web` | Web administration interface | 80/tcp, 443/tcp |

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

The Pi-hole admin interface is available at:

```
https://10.0.9.2
```

### Updating Pi-hole Configuration

To apply configuration changes to the Pi-hole instance, run:

```bash
colmena apply --on orangepi-zero3 --impure
```
