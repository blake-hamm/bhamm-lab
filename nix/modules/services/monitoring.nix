{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.cfg.monitoring;
in
{
  options.cfg.monitoring = {
    enable = mkEnableOption "Prometheus exporters and Promtail log shipping";

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

    promtail = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Promtail journald log shipping to Loki";
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

    services.promtail = mkIf cfg.promtail.enable {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };
        clients = [{
          url = cfg.promtail.lokiUrl;
        }];
        scrape_configs = [{
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
              host = config.networking.hostName;
            };
          };
          relabel_configs = [
            {
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "unit";
            }
          ];
        }];
      };
    };
  };
}
