# Shared configuration for orangepi-zero3
# Used by both sd-image.nix (initial image) and default.nix (deployment)
{ config, ... }:
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
        address = "10.0.9.3";
        gateway = "10.0.9.5";
        nameservers = [ "10.0.9.1" "9.9.9.9" ];
      };
    };
  };

}
