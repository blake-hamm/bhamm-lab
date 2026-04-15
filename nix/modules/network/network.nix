{ config, lib, host, ... }:
let
  netCfg = config.cfg.networking;
in
{
  options.cfg.networking = {
    backend = lib.mkOption {
      type = lib.types.enum [ "networkmanager" "networkd" ];
      default = "networkmanager";
      description = "The networking backend to use.";
    };
    static = {
      interface = lib.mkOption {
        type = lib.types.str;
        default = "eth0";
        description = "The primary network interface.";
      };
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The static IPv4 address.";
      };
      prefixLength = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = 24;
        description = "The IPv4 subnet prefix length.";
      };
      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The default gateway address.";
      };
      nameservers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "9.9.9.9" "1.1.1.1" ];
        description = "List of DNS nameservers.";
      };
    };
  };

  config = {
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
  };
}
