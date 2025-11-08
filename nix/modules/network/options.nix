{ lib, ... }:

{
  options.cfg = {
    # Networking
    networking = {
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

    vpn.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable VPN";
    };
  };
}
