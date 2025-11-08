{ config, lib, host, ... }:
let
  netCfg = config.cfg.networking;
in
{

  # Conditionally configure the networking backend
  networking = lib.mkMerge [
    { hostName = host; }
    (lib.mkIf (netCfg.backend == "networkmanager") {
      networkmanager.enable = true;
    })

    (lib.mkIf (netCfg.backend == "networkd") {
      networkmanager.enable = false;
      useDHCP = false;
      useNetworkd = true;
      nameservers = netCfg.static.nameservers;
      interfaces."${netCfg.static.interface}" = {
        useDHCP = false;
        ipv4.addresses = [{
          address = netCfg.static.address;
          prefixLength = netCfg.static.prefixLength;
        }];
      };
      defaultGateway = {
        address = netCfg.static.gateway;
        interface = netCfg.static.interface;
      };
    })
  ];
}
