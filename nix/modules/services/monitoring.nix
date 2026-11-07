{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.cfg.monitoring;
in
{
  options.cfg.monitoring = {
    enable = mkEnableOption "Prometheus exporters and Alloy log shipping";

    nodeExporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Prometheus node_exporter";
      };
      port = mkOption {
        type = types.port;
        default = 9100;
        description = "Port for node_exporter";
      };
    };

    systemdExporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Prometheus systemd_exporter";
      };
      port = mkOption {
        type = types.port;
        default = 9558;
        description = "Port for systemd_exporter";
      };
    };

    smartctlExporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Prometheus smartctl_exporter";
      };
      port = mkOption {
        type = types.port;
        default = 9633;
        description = "Port for smartctl_exporter";
      };
    };

    logs = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Ship the systemd journal to Loki with Grafana Alloy";
      };
      lokiUrl = mkOption {
        type = types.str;
        default = "https://loki.bhamm-lab.com/loki/api/v1/push";
        description = "Loki push API URL";
      };
    };
  };

  config = mkIf cfg.enable {
    services.prometheus.exporters.node = mkIf cfg.nodeExporter.enable {
      enable = true;
      port = cfg.nodeExporter.port;
      enabledCollectors = [ "systemd" ];
      openFirewall = true;
    };

    services.prometheus.exporters.systemd = mkIf cfg.systemdExporter.enable {
      enable = true;
      port = cfg.systemdExporter.port;
      openFirewall = true;
    };

    services.prometheus.exporters.smartctl = mkIf cfg.smartctlExporter.enable {
      enable = true;
      port = cfg.smartctlExporter.port;
      openFirewall = true;
    };

    # promtail was removed from nixpkgs in 26.05 (end of life), alloy is the
    # replacement. The config lives in /etc/alloy so it can be reloaded.
    services.alloy = mkIf cfg.logs.enable {
      enable = true;
    };

    environment.etc."alloy/config.alloy" = mkIf cfg.logs.enable {
      text = ''
        loki.relabel "journal" {
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "unit"
          }
          forward_to = []
        }

        loki.source.journal "journal" {
          max_age       = "12h"
          relabel_rules = loki.relabel.journal.rules
          labels = {
            job  = "systemd-journal",
            host = "${config.networking.hostName}",
          }
          forward_to = [loki.write.loki.receiver]
        }

        loki.write "loki" {
          endpoint {
            url = "${cfg.logs.lokiUrl}"
          }
        }
      '';
    };
  };
}
