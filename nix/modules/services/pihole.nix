{ config, lib, ... }:

{
  config = lib.mkIf config.cfg.pihole.enable {
    services.resolved = {
      enable = true;
      extraConfig = ''
        DNSStubListener=no
        MulticastDNS=off
      '';
    };
    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;
      openFirewallWebserver = true;
      settings = {
        dns = {
          upstreams = [ "10.0.9.1" ];
          listeningMode = "ALL";
        };
        dhcp = {
          active = false;
        };
      };
      lists = [
        {
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          description = "StevenBlack Unified";
          type = "block";
          enabled = true;
        }
        {
          url = "https://big.oisd.nl";
          description = "OISD Big";
          type = "block";
          enabled = true;
        }
      ];
    };
    services.pihole-web = {
      enable = true;
      ports = [ "80r" "443s" ];
    };
    # The following silences a benign FTL.log warning:
    # WARNING API: Failed to read /etc/pihole/versions (key: internal_error)
    systemd.tmpfiles.rules = [
      "f /etc/pihole/versions 0644 pihole pihole - -"
    ];
  };
}
