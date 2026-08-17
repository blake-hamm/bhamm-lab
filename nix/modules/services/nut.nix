{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.cfg.nut;
in
{
  options.cfg.nut = {
    enable = mkEnableOption "NUT UPS server";

    mode = mkOption {
      type = types.enum [ "standalone" "netserver" "netclient" ];
      default = "netserver";
      description = "NUT operating mode";
    };

    upsName = mkOption {
      type = types.str;
      default = "cyberpower";
      description = "UPS name in ups.conf";
    };

    driver = mkOption {
      type = types.str;
      default = "usbhid-ups";
      description = "NUT driver for UPS";
    };

    port = mkOption {
      type = types.str;
      default = "auto";
      description = "Port for UPS driver";
    };

    directives = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra directives for ups.conf";
      example = [ "vendorid = 0764" "productid = 0601" ];
    };

    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = "Addresses for upsd to listen on";
    };

    passwordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to password file for upsmon/upsd users";
    };

    exporter = {
      enable = mkEnableOption "Prometheus NUT exporter";

      nutServer = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "NUT server address for the exporter to connect to";
      };
    };
  };

  config = mkIf cfg.enable {
    power.ups = {
      enable = true;
      openFirewall = true;
      mode = cfg.mode;
      ups.${cfg.upsName} = {
        driver = cfg.driver;
        port = cfg.port;
        directives = cfg.directives;
      };
      upsd.listen = map (addr: { address = addr; port = 3493; }) cfg.listenAddresses;
      users."nut-admin" = mkIf (cfg.passwordFile != null) {
        passwordFile = cfg.passwordFile;
        upsmon = "primary";
        instcmds = [ "ALL" ];
      };
      upsmon.monitor.${cfg.upsName} = mkIf (cfg.passwordFile != null) {
        system = "${cfg.upsName}@localhost";
        powerValue = 1;
        user = "nut-admin";
        passwordFile = cfg.passwordFile;
        type = "primary";
      };
      upsmon.settings = {
        BATTERYLEVEL = "20";
        MINUTES = "3";
        FINALDELAY = "30";
      };
    };

    services.prometheus.exporters.nut = mkIf cfg.exporter.enable {
      enable = true;
      openFirewall = true;
      nutServer = cfg.exporter.nutServer;
    };

    # After an unclean shutdown NUT leaves stale PID files in its state
    # directory, so upsd/upsdrvctl refuse to start on the next boot with
    # "A previous upsd instance is already running!" or "Duplicate driver
    # instance detected!". Clean them before starting.
    systemd.services.upsd.serviceConfig.ExecStartPre = lib.mkBefore [
      "${pkgs.coreutils}/bin/rm -f /var/lib/nut/upsd.pid"
    ];

    systemd.services.upsdrv = {
      serviceConfig.ExecStartPre = lib.mkBefore [
        "${pkgs.coreutils}/bin/rm -f /var/lib/nut/${cfg.driver}-${cfg.upsName}.pid"
      ];
      serviceConfig.ExecStop = lib.mkDefault "${pkgs.nut}/bin/upsdrvctl -u root stop";
    };
  };
}
