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
    # Create user for health check scripts
    users.users.keepalived_script = {
      isSystemUser = true;
      group = "keepalived_script";
      description = "Keepalived script user";
    };
    users.groups.keepalived_script = { };

    services.keepalived = {
      enable = true;
      openFirewall = true;
      enableScriptSecurity = true;

      vrrpScripts.check_pihole = {
        script = "${pkgs.procps}/bin/pgrep -x pihole-FTL";
        interval = 1;
        weight = 0;
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
