# Plan: Orange Pi Zero3 Redundant Pi-hole with Keepalived VIP

## Overview

Deploy a second Orange Pi Zero3 as a redundant Pi-hole DNS server with automatic failover using Keepalived (VRRP). The existing Pi-hole will be renumbered, and the current IP (`10.0.9.2`) will become the floating VIP.

## Goals

- Add Pi-hole redundancy with automatic failover (< 3 second switchover)
- Zero DNS client reconfiguration required
- Maintain independent admin access to each Pi-hole
- Infrastructure-wide DNS references remain unchanged

## Current State

- **Existing Orange Pi Zero3**: Running at `10.0.9.2` with NixOS + Pi-hole + FTL DNS
- **Primary DNS**: Used by all infrastructure (Talos, Proxmox, VLANs) via `10.0.9.2`
- **Upstream**: Points to OPNsense (`10.0.9.1`) running unbound
- **Architecture**: `aarch64-linux` (ARM64)
- **Network**: Static IP via systemd-networkd on interface `end0`
- **Blocklists**: StevenBlack Unified + OISD Big

## Target State

### IP Allocation (VLAN 9 - 10.0.9.0/24)

| IP Address | Role | Host |
|------------|------|------|
| `10.0.9.1` | Gateway | OPNsense firewall / unbound resolver |
| `10.0.9.2` | **VIP** | Keepalived floating IP - all DNS clients use this |
| `10.0.9.3` | Static | Pi-hole primary (orangepi-zero3) - VRRP MASTER |
| `10.0.9.4` | Static | Pi-hole secondary (orangepi-zero3-backup) - VRRP BACKUP |

### DNS Flow

```
Clients → 10.0.9.2 (VIP) → Keepalived → Active Pi-hole → 10.0.9.1 (OPNsense/unbound) → Internet
```

If primary fails, VIP moves to backup (~1-3 seconds), clients continue using `10.0.9.2`.

### Keepalived Configuration

**Primary (orangepi-zero3)**
- State: MASTER
- Priority: 100
- Virtual IP: 10.0.9.2/24
- Interface: end0
- VRRP Instance: pihole_vip
- Health Check: Verify pihole-ftl process is running

**Secondary (orangepi-zero3-backup)**
- State: BACKUP
- Priority: 90
- Virtual IP: 10.0.9.2/24
- Interface: end0
- VRRP Instance: pihole_vip
- Health Check: Verify pihole-ftl process is running

**Failover Behavior**
- MASTER loses pihole-ftl: VIP moves to BACKUP
- MASTER recovers: VIP preempts back to MASTER (configurable)
- VRRP multicast: Sent between 10.0.9.3 and 10.0.9.4 (needs firewall rules)

## Implementation Steps

### Phase 1: NixOS Configuration

#### 1.1 Create New Host Directory: `nix/hosts/orangepi-zero3-backup/`

```
nix/hosts/orangepi-zero3-backup/
├── default.nix      # Host entry with deploy metadata
├── config.nix       # Shared config (static IP 10.0.9.4, keepalived)
├── hardware.nix     # Hardware scan (stub initially)
└── sd-image.nix     # SD card image builder
```

**default.nix**
```nix
{
  system = "aarch64-linux";

  deploy = {
    tags = [ "orangepi" "sbc" "server" "backup" ];
    targetHost = "10.0.9.4";
  };

  imports = [
    ./hardware.nix
    ./config.nix
    ./../../profiles/sbc.nix
  ];
}
```

**config.nix**
```nix
{
  cfg = {
    orangepi-zero3.enable = true;
    pihole.enable = true;
    keepalived = {
      enable = true;
      state = "BACKUP";
      priority = 90;
      virtualIp = "10.0.9.2";
      interface = "end0";
    };
    networking = {
      backend = "networkd";
      static = {
        interface = "end0";
        address = "10.0.9.4";
        gateway = "10.0.9.1";
        nameservers = [ "10.0.9.1" "9.9.9.9" ];
      };
    };
  };
}
```

**sd-image.nix** (identical to existing)
```nix
{ lib, pkgs, ... }:
let
  bootloaderPackage = pkgs.ubootOrangePiZero3;
in
{
  imports = [
    ../../profiles/sbc.nix
    ./config.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  sdImage = {
    compressImage = true;
    postBuildCommands = ''
      dd if=${bootloaderPackage}/u-boot-sunxi-with-spl.bin of=$img \
        bs=1024 seek=8 conv=notrunc
    '';
  };
}
```

**hardware.nix** (initial stub)
```nix
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [ ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];
  fileSystems."/" = { device = "/dev/disk/by-uuid/PLACEHOLDER"; fsType = "ext4"; };
  swapDevices = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
```

#### 1.2 Update Existing Host: `nix/hosts/orangepi-zero3/`

**config.nix** - Change static IP to 10.0.9.3 and add keepalived

```nix
{
  cfg = {
    orangepi-zero3.enable = true;
    pihole.enable = true;
    keepalived = {
      enable = true;
      state = "MASTER";
      priority = 100;
      virtualIp = "10.0.9.2";
      interface = "end0";
    };
    networking = {
      backend = "networkd";
      static = {
        interface = "end0";
        # RENUMBERED: Was 10.0.9.2, now 10.0.9.3
        address = "10.0.9.3";
        gateway = "10.0.9.1";
        nameservers = [ "10.0.9.1" "9.9.9.9" ];
      };
    };
  };
}
```

#### 1.3 Create Keepalived Module: `nix/modules/services/keepalived.nix`

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.cfg.keepalived;
in
{
  options.cfg.keepalived = {
    enable = mkEnableOption "Keepalived VRRP for high availability";

    state = mkOption {
      type = types.enum [ "MASTER" "BACKUP" ];
      description = "VRRP state (MASTER or BACKUP)";
      default = "BACKUP";
    };

    priority = mkOption {
      type = types.int;
      description = "VRRP priority (higher = preferred for MASTER)";
      default = 100;
    };

    virtualIp = mkOption {
      type = types.str;
      description = "Virtual IP address (with CIDR)";
      example = "10.0.9.2/24";
    };

    interface = mkOption {
      type = types.str;
      description = "Network interface for VRRP";
      default = "end0";
    };

    virtualRouterId = mkOption {
      type = types.int;
      description = "Unique VRRP virtual router ID (1-255)";
      default = 51;
    };

    authentication = {
      authType = mkOption {
        type = types.enum [ "PASS" "AH" ];
        default = "PASS";
        description = "Authentication type";
      };

      authPass = mkOption {
        type = types.str;
        default = "changeme";
        description = "Authentication password (8 chars max for PASS)";
      };
    };
  };

  config = mkIf cfg.enable {
    services.keepalived = {
      enable = true;
      # VRRP instance configuration
      extraConfig = ''
        global_defs {
          router_id ${config.networking.hostName}
          script_user root
          enable_script_security
        }

        vrrp_script check_pihole {
          script "${pkgs.procps}/bin/pgrep -f 'pihole-FTL'"
          interval 2
          weight 2
          fall 2
          rise 2
        }

        vrrp_instance pihole_vip {
          state ${cfg.state}
          interface ${cfg.interface}
          virtual_router_id ${toString cfg.virtualRouterId}
          priority ${toString cfg.priority}
          advert_int 1

          authentication {
            auth_type ${cfg.authentication.authType}
            auth_pass ${cfg.authentication.authPass}
          }

          virtual_ipaddress {
            ${cfg.virtualIp}/24
          }

          track_script {
            check_pihole
          }

          ${optionalString (cfg.state == "MASTER") ''
            # Preempt on recovery (optional - remove to stay on BACKUP)
            preempt_delay 5
          ''}
        }
      '';
    };

    # Firewall rules for VRRP
    networking.firewall.allowedUDPPorts = [ 112 ]; # VRRP protocol
    networking.firewall.extraInputRules = ''
      # Allow VRRP multicast
      ip protocol vrrp accept
    '';
  };
}
```

#### 1.4 Update Module Imports

**`nix/modules/services/options.nix`** - Add keepalived options

```nix
keepalived = {
  enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Keepalived VRRP for high availability";
  };

  state = lib.mkOption {
    type = lib.types.enum [ "MASTER" "BACKUP" ];
    default = "BACKUP";
    description = "VRRP state for this node";
  };

  priority = lib.mkOption {
    type = lib.types.int;
    default = 100;
    description = "VRRP priority (higher is preferred)";
  };

  virtualIp = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Virtual IP address for the VIP";
  };

  interface = lib.mkOption {
    type = lib.types.str;
    default = "end0";
    description = "Network interface for VRRP";
  };
};
```

**`nix/modules/services/default.nix`** - Import keepalived module

```nix
{ imports = [
  ./options.nix
  ./backups.nix
  ./docker.nix
  ./pihole.nix
  ./pre-commit.nix
  ./samba.nix
  ./virtualization.nix
  ./keepalived.nix  # NEW
]; }
```

#### 1.5 Update flake.nix

Add SD image builder for the new host:

```nix
# In flake.nix, under nixosConfigurations:

orangepi-zero3-backup-image = nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    (import ./nix/hosts/orangepi-zero3-backup/sd-image.nix)
  ];
  specialArgs = {
    host = "orangepi-zero3-backup";
    inherit self inputs shared;
  };
};
```

### Phase 2: Infrastructure Updates

**No DNS IP changes required** — `10.0.9.2` remains the DNS server for all infrastructure. However, OPNsense firewall rules need updates for VRRP and the new host.

#### 2.1 OPNsense Firewall Rules

**`ansible/roles/opnsense/tasks/rules.yml`** - Add VRRP and new host rules

```yaml
# Add these rules to the common_firewall_rules list:

# Allow VRRP between Pi-holes (IP protocol 112)
{
  "description": "Allow VRRP between Pi-hole nodes",
  "interface": "lan",
  "sequence": 2,
  "ip_protocol": "inet",
  "protocol": "VRRP",  # or IP protocol 112
  "source_net": "10.0.9.3",
  "destination_net": "10.0.9.4"
}

# Allow reverse VRRP
{
  "description": "Allow VRRP from backup to primary",
  "interface": "lan",
  "sequence": 2,
  "ip_protocol": "inet",
  "protocol": "VRRP",
  "source_net": "10.0.9.4",
  "destination_net": "10.0.9.3"
}

# Allow new backup Pi-hole DNS (optional - VIP handles most traffic)
{
  "description": "Allow VLAN DNS to backup Pi-hole",
  "interface": "{{ item.interface }}",
  "sequence": 2,
  "ip_protocol": "inet",
  "protocol": "UDP",
  "source_net": "{{ item.name }}Network",
  "destination_net": "10.0.9.4",
  "destination_port": 53
}

# Allow backup Pi-hole DNS replies
{
  "description": "Allow backup Pi-hole DNS replies",
  "interface": "lan",
  "sequence": 2,
  "ip_protocol": "inet",
  "protocol": "UDP",
  "source_net": "10.0.9.4",
  "source_port": 53,
  "destination_net": "{{ item.name }}Network"
}
```

**Note**: OPNsense UI may need manual VRRP protocol rule or use IP protocol number 112.

#### 2.2 Dashboard Update

**`kubernetes/manifests/core/dashy/config-all.yaml`** - Add entry for backup Pi-hole

```yaml
# Add to services section:
- name: "Pi-hole Backup"
  icon: "hl-pihole"
  url: "https://10.0.9.4/"
  description: "Secondary Pi-hole DNS (VRRP BACKUP)"
  category: "Network"
```

### Phase 3: Bootstrap Procedure

#### 3.1 Pre-deployment Checklist

- [ ] Build SD image for orangepi-zero3-backup
- [ ] Flash SD card
- [ ] Boot new Orange Pi Zero3
- [ ] Verify network connectivity (10.0.9.4 accessible via SSH on port 4185)
- [ ] Run `nixos-generate-config` on new host and copy hardware.nix
- [ ] Deploy NixOS config to both hosts (Colmena)

#### 3.2 Deployment Order

1. **Build and deploy primary (existing) first**
   ```bash
   # This will:
   # - Change static IP from 10.0.9.2 -> 10.0.9.3
   # - Add Keepalived with VIP 10.0.9.2
   # - Keep pihole-ftl running
   colmena apply --on orangepi-zero3 --impure
   ```

2. **Wait and verify**
   - Check `10.0.9.2` is still reachable (should be VIP now)
   - Check `10.0.9.3` is reachable (new static IP)
   - Verify Pi-hole admin at `https://10.0.9.2/admin` works
   - Verify DNS resolution works: `dig @10.0.9.2 google.com`

3. **Build and flash backup SD card**
   ```bash
   nix build .#nixosConfigurations.orangepi-zero3-backup-image.config.system.build.sdImage
   # Flash to SD card
   ```

4. **Boot backup Pi-hole**
   - Insert SD, power on
   - Wait for boot
   - Verify `10.0.9.4` reachable via SSH

5. **Deploy backup configuration**
   ```bash
   colmena apply --on orangepi-zero3-backup --impure
   ```

6. **Verify VIP and failover**
   ```bash
   # Check VIP on primary
   ssh orangepi-zero3 ip addr show end0
   # Should show: 10.0.9.3/24 and 10.0.9.2/24

   # Check VIP on backup
   ssh orangepi-zero3-backup ip addr show end0
   # Should show: 10.0.9.4/24 only (VIP not assigned to BACKUP)
   ```

#### 3.3 Failover Testing

1. **Test active DNS**
   ```bash
   # Continuous DNS queries
   watch -n 1 'dig @10.0.9.2 google.com +short'
   ```

2. **Stop primary Pi-hole**
   ```bash
   ssh orangepi-zero3 systemctl stop pihole-ftl
   ```

3. **Verify failover**
   - Check VIP moved to backup: `ssh orangepi-zero3-backup ip addr show end0`
   - DNS queries should continue working (1-3 second gap possible)
   - Pi-hole admin at `https://10.0.9.2` should work via backup

4. **Restore primary**
   ```bash
   ssh orangepi-zero3 systemctl start pihole-ftl
   ```

5. **Verify preemption** (if enabled)
   - VIP should return to primary after ~5 seconds
   - Check: `ssh orangepi-zero3 ip addr show end0`

#### 3.4 Update Ansible/OPNsense

After both Pi-holes are stable, run Ansible to update firewall rules:

```bash
ansible-playbook ansible/main.yml --tags opnsense
```

### Phase 4: Documentation Updates

#### 4.1 Hardware Inventory

**`docker/docs-site/docs/architecture/hardware.md`**

Update SBC table:

```markdown
| Name | Hardware | Network | IP Address | OS | Purpose |
|------|----------|---------|------------|----|---------|
| Orange Pi Zero3 | ARM64 / Allwinner H618 | LAN (VLAN 9) | 10.0.9.3 (static) + 10.0.9.2 (VIP) | NixOS | Pi-hole DNS (Primary) |
| Orange Pi Zero3 Backup | ARM64 / Allwinner H618 | LAN (VLAN 9) | 10.0.9.4 (static) + 10.0.9.2 (VIP) | NixOS | Pi-hole DNS (Backup) |
```

#### 4.2 Software Architecture

**`docker/docs-site/docs/architecture/software.md`**

Update DNS section to mention redundancy:

```markdown
### DNS Infrastructure

Primary DNS servers run on Orange Pi Zero3 devices with Pi-hole for ad-blocking:

- **VIP**: `10.0.9.2` — Floating IP via Keepalived (VRRP)
- **Primary**: `10.0.9.3` — Orange Pi Zero3 (MASTER)
- **Backup**: `10.0.9.4` — Orange Pi Zero3 Backup (BACKUP)

Both Pi-hole instances:
- Point upstream to OPNsense unbound (`10.0.9.1`)
- Use identical blocklists (StevenBlack Unified + OISD Big)
- Provide ad-blocking for all lab infrastructure
- Support independent web admin access at their static IPs

Failover: Automatic via VRRP, < 3 second switchover.
```

#### 4.3 Operations Guide

**`docker/docs-site/docs/operations/pihole.md`**

Update with dual-host operations:

```markdown
## Pi-hole Operations

### Hosts

| Host | IP | Role | Admin URL |
|------|-----|------|-----------|
| orangepi-zero3 | 10.0.9.3 | Primary (MASTER) | https://10.0.9.3/admin |
| orangepi-zero3-backup | 10.0.9.4 | Backup (BACKUP) | https://10.0.9.4/admin |
| VIP | 10.0.9.2 | Active DNS | https://10.0.9.2/admin |

### Deployment

```bash
# Deploy primary
colmena apply --on orangepi-zero3 --impure

# Deploy backup
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
```

### Maintenance

**Updating blocklists on both hosts:**
Since Pi-hole sync is not configured, update lists manually or via script on both hosts.

**Graceful failover for maintenance:**
```bash
# Lower priority on primary to trigger failover
ssh orangepi-zero3 systemctl stop keepalived
# VIP moves to backup automatically

# Perform maintenance, then restore
ssh orangepi-zero3 systemctl start keepalived
```
```

## Post-Implementation Verification

### Network Tests

```bash
# 1. Verify all IPs are reachable
curl -I https://10.0.9.2/admin  # VIP
curl -I https://10.0.9.3/admin  # Primary static
curl -I https://10.0.9.4/admin  # Backup static

# 2. Verify DNS resolution
dig @10.0.9.2 google.com +short
dig @10.0.9.3 google.com +short
dig @10.0.9.4 google.com +short

# 3. Verify blocklists work
dig @10.0.9.2 doubleclick.net  # Should return 0.0.0.0 or NXDOMAIN

# 4. Test failover
curl -I https://10.0.9.2/admin  # Should work via VIP
ssh orangepi-zero3 systemctl stop pihole-ftl
sleep 5
curl -I https://10.0.9.2/admin  # Should still work (now via backup)
ssh orangepi-zero3 systemctl start pihole-ftl
```

### Infrastructure Validation

- [ ] Talos nodes can resolve DNS via `10.0.9.2`
- [ ] Proxmox hosts can resolve DNS via `10.0.9.2`
- [ ] All VLAN clients can resolve DNS
- [ ] Dashboard shows both Pi-hole instances
- [ ] OPNsense firewall rules allow VRRP traffic
- [ ] Keepalived logs show proper VRRP state transitions

## Rollback Plan

If issues occur:

1. **Immediate**: Stop keepalived on both hosts to release VIP
   ```bash
   colmena exec --on orangepi-zero3 --on orangepi-zero3-backup -- systemctl stop keepalived
   ```

2. **Revert primary to old config** (static IP 10.0.9.2):
   ```bash
   # Edit nix/hosts/orangepi-zero3/config.nix to remove keepalived and set address = 10.0.9.2
   colmena apply --on orangepi-zero3 --impure
   ```

3. **Power off backup Pi-hole** until resolved

## Future Improvements

1. **Gravity Sync**: Consider adding [Gravity Sync](https://github.com/vmstan/gravity-sync) for Pi-hole database synchronization (whitelists, blacklists, stats)
2. **Telegraf/Metrics**: Export Pi-hole metrics to Prometheus for both instances
3. **Anycast**: For larger scale, consider BGP Anycast instead of VRRP
4. **Split-horizon DNS**: Configure different blocklists per subnet if needed

## References

- [NixOS Keepalived module](https://search.nixos.org/options?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=keepalived)
- [Keepalived documentation](https://www.keepalived.org/documentation.html)
- [VRRP RFC 3768](https://datatracker.ietf.org/doc/html/rfc3768)
- [Pi-hole FTL DNS](https://docs.pi-hole.net/ftldns/)
