{ config, lib, ... }:

{
  config = lib.mkIf config.cfg.pihole.enable {
    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;
      openFirewallWebserver = true;
      settings = {
        dns = {
          upstreams = [ "10.0.9.1" "9.9.9.9" "1.1.1.1" ];
          listeningMode = "ALL";
          hosts = [ "127.0.0.1 localhost" ];
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
  };
}
