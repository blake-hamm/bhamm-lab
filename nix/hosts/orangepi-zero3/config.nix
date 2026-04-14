# Shared configuration for orangepi-zero3
# Used by both sd-image.nix (initial image) and default.nix (deployment)
{ config, ... }:
{
  cfg = {
    orangepi-zero3.enable = true;
    pihole.enable = true;
    nut = {
      enable = true;
      mode = "netserver";
      driver = "usbhid-ups";
      directives = [
        "vendorid = 0764"
        "productid = 0601"
      ];
      listenAddresses = [ "127.0.0.1" ];
      passwordFile = config.sops.secrets.nut_password.path;
    };
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
        gateway = "10.0.9.1";
        nameservers = [ "10.0.9.1" "9.9.9.9" ];
      };
    };
  };

}
