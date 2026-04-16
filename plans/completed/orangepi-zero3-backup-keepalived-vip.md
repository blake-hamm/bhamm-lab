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
- Health Check: Verify pihole-FTL process is running

**Secondary (orangepi-zero3-backup)**
- State: BACKUP
- Priority: 90
- Virtual IP: 10.0.9.2/24
- Interface: end0
- VRRP Instance: pihole_vip
- Health Check: Verify pihole-FTL process is running

**Failover Behavior**
- MASTER loses pihole-ftl: VIP moves to BACKUP
- MASTER recovers: VIP preempts back to MASTER (configurable)
- VRRP multicast: Sent between 10.0.9.3 and 10.0.9.4 (needs firewall rules)

## Critical Bug Fix: Keepalived Health Check Weight

### The Bug in Original Plan

Original plan used `weight = 2` for health check:

| State | Primary Priority | Backup Priority |
|-------|------------------|-----------------|
| Healthy | 100 + 2 = **102** | 90 + 2 = **92** |
| Primary dead | **100** (weight removed) | 92 |

**Problem**: When primary's pihole dies, priority drops to 100. Since 100 > 92 (backup), **VIP stays on dead primary!** DNS broken. No failover.

### The Fix: Use `weight = 0`

With `weight = 0`:

| State | Primary Priority | Backup Priority |
|-------|------------------|-----------------|
| Healthy | **100** | **90** |
| Primary dead | **FAULT** (removed from VRRP) | 90 |

When health check fails with `weight = 0`, VRRP instance enters **FAULT state**. VRRP removes FAULT node from election. Backup becomes MASTER. VIP moves. DNS works.

**Bottom line**: Use `weight = 0` in vrrp_scripts for this failover use case.

## Implementation Steps

### Phase 1: NixOS Configuration

#### 1.1 Create Keepalived Module: `nix/modules/services/keepalived.nix`

Uses structured NixOS `services.keepalived` options (vrrpInstances/vrrpScripts) with SOPS-managed authentication:

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
      default = "BACKUP";
      description = "VRRP state (MASTER or BACKUP)";
    };

    priority = mkOption {
      type = types.int;
      default = 100;
      description = "VRRP priority (higher = preferred for MASTER)";
    };

    virtualIp = mkOption {
      type = types.str;
      description = "Virtual IP address for the VIP";
      example = "10.0.9.2";
    };

    interface = mkOption {
      type = types.str;
      default = "end0";
      description = "Network interface for VRRP";
    };

    virtualRouterId = mkOption {
      type = types.ints.between 1 255;
      default = 51;
      description = "Unique VRRP virtual router ID (1-255)";
    };

    authPassFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to an environment file containing KEEPALIVED_AUTH_PASS for VRRP authentication.
        Use sops.templates for SOPS-managed secrets. Set to null to disable authentication.
      '';
      example = "config.sops.templates.\"keepalived-env\".path";
    };
  };

  config = mkIf cfg.enable {
    services.keepalived = {
      enable = true;
      openFirewall = true;  # Handles VRRP/AH iptables rules automatically
      enableScriptSecurity = true;

      vrrpScripts.check_pihole = {
        script = "${pkgs.procps}/bin/pgrep -x pihole-FTL";
        interval = 1;
        weight = 0;  # CRITICAL: weight=0 causes FAULT state on failure (correct failover)
        fall = 2;
        rise = 2;
        user = "keepalived_script";
      };

      vrrpInstances.pihole_vip = {
        interface = cfg.interface;
        state = cfg.state;
        virtualRouterId = cfg.virtualRouterId;
        priority = cfg.priority;
        virtualIps = [{ addr = "${cfg.virtualIp}/24"; }];
        trackScripts = [ "check_pihole" ];
        extraConfig =
          ''
            advert_int 1
          ''
          + optionalString (cfg.state == "MASTER") ''
            preempt_delay 5
          ''
          + optionalString (cfg.authPassFile != null) ''
            authentication {
              auth_type PASS
              auth_pass ''${KEEPALIVED_AUTH_PASS}
            }
          '';
      };

      secretFile = mkIf (cfg.authPassFile != null) cfg.authPassFile;
    };
  };
}
```

**Key improvements over original plan:**
- Uses structured `vrrpInstances`/`vrrpScripts` instead of raw `extraConfig`
- `weight = 0` for correct failover behavior
- `openFirewall = true` instead of manual iptables rules
- SOPS-managed auth via `secretFile` and envsubst

#### 1.2 Update Module Imports

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

  virtualRouterId = lib.mkOption {
    type = lib.types.int;
    default = 51;
    description = "Unique VRRP virtual router ID (1-255)";
  };

  authPassFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Path to environment file with KEEPALIVED_AUTH_PASS for VRRP authentication";
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

#### 1.3 Add VRRP Auth Password to SOPS

Edit `nix/secrets.yaml` and add:

```yaml
keepalived_auth_pass: <8-character-password>
```

Then encrypt: `sops -e -i nix/secrets.yaml`

#### 1.4 Update Existing Host: `nix/hosts/orangepi-zero3/`

**config.nix** - Change static IP to 10.0.9.3 and add keepalived + SOPS

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
      authPassFile = config.sops.templates."keepalived-env".path;
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

  # SOPS secrets for Keepalived authentication
  sops.secrets.keepalived_auth_pass = {
    sopsFile = ../../secrets.yaml;
    key = "keepalived_auth_pass";
  };

  sops.templates."keepalived-env".content = ''
    KEEPALIVED_AUTH_PASS=${config.sops.placeholder.keepalived_auth_pass}
  '';
}
```

**IMPORTANT**: Keep `targetHost = "10.0.9.2"` in `default.nix` for initial deployment (chicken-and-egg problem). Will update to `10.0.9.3` after deployment.

#### 1.5 Create New Host Directory: `nix/hosts/orangepi-zero3-backup/`

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
      authPassFile = config.sops.templates."keepalived-env".path;
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

  # SOPS secrets for Keepalived authentication
  sops.secrets.keepalived_auth_pass = {
    sopsFile = ../../secrets.yaml;
    key = "keepalived_auth_pass";
  };

  sops.templates."keepalived-env".content = ''
    KEEPALIVED_AUTH_PASS=${config.sops.placeholder.keepalived_auth_pass}
  '';
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

**hardware.nix** (initial stub - replace after first boot)
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

#### 1.6 Update flake.nix

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
  "protocol": "112",  # IP protocol number for VRRP
  "source_net": "10.0.9.3",
  "destination_net": "10.0.9.4"
}

# Allow reverse VRRP
{
  "description": "Allow VRRP from backup to primary",
  "interface": "lan",
  "sequence": 2,
  "ip_protocol": "inet",
  "protocol": "112",
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

- [ ] Add VRRP auth password to `nix/secrets.yaml` and encrypt
- [ ] Build SD image for orangepi-zero3-backup
- [ ] Flash SD card
- [ ] Boot new Orange Pi Zero3
- [ ] Verify network connectivity (10.0.9.4 accessible via SSH on port 4185)
- [ ] Run `nixos-generate-config` on new host and copy hardware.nix
- [ ] Deploy NixOS config to both hosts (Colmena)

#### 3.2 Deployment Order

**CRITICAL: Handle chicken-and-egg problem with IP change**

1. **Prepare and commit all code changes** (Phases 1 & 2)

2. **Build and deploy primary (existing) first**
   ```bash
   # This will:
   # - Change static IP from 10.0.9.2 -> 10.0.9.3
   # - Add Keepalived with VIP 10.0.9.2
   # - Keep pihole-ftl running
   colmena apply --on orangepi-zero3 --impure
   ```
   **Expect**: SSH connection will drop during IP change. Wait ~30s before next step.

3. **Wait and verify**
   - Check `10.0.9.2` is still reachable (should be VIP now via keepalived)
   - Check `10.0.9.3` is reachable (new static IP)
   - Verify Pi-hole admin at `https://10.0.9.2/admin` works
   - Verify DNS resolution works: `dig @10.0.9.2 google.com`

4. **Update targetHost in primary's default.nix**
   ```nix
   # nix/hosts/orangepi-zero3/default.nix
   deploy.targetHost = "10.0.9.3";  # Change from 10.0.9.2
   ```
   Commit this change. Now colmena will connect to the new static IP for future deployments.

5. **Build and flash backup SD card**
   ```bash
   nix build .#nixosConfigurations.orangepi-zero3-backup-image.config.system.build.sdImage
   # Flash to SD card
   ```

6. **Boot backup Pi-hole**
   - Insert SD, power on
   - Wait for boot
   - Verify `10.0.9.4` reachable via SSH on port 4185

7. **Generate hardware config for backup**
   ```bash
   ssh -p 4185 root@10.0.9.4 nixos-generate-config --show-hardware-config > \
     nix/hosts/orangepi-zero3-backup/hardware.nix
   ```
   Commit the updated hardware.nix.

8. **Deploy backup configuration**
   ```bash
   colmena apply --on orangepi-zero3-backup --impure
   ```

9. **Verify VIP and failover**
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
