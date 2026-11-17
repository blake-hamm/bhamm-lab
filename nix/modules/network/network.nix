{ config, lib, host, ... }:
let
  netCfg = config.cfg.networking;

  # `cfg.networking.static` is a compatibility shim for a single static
  # interface. An explicit `cfg.networking.interfaces.<if>` wins over it.
  effectiveInterfaces =
    netCfg.interfaces
    // (
      if netCfg.static.address != null
        && !(netCfg.interfaces ? ${netCfg.static.interface})
      then {
        ${netCfg.static.interface} = {
          mode = "static";
          address = netCfg.static.address;
          prefixLength = netCfg.static.prefixLength;
          gateway = netCfg.static.gateway;
          metric = null;
          nameservers = netCfg.static.nameservers;
        };
      }
      else { }
    );

  # attrNames is sorted, so the emitted order is stable.
  interfaceNames = lib.attrNames effectiveInterfaces;

  gatewayInterfaces =
    lib.filter (n: effectiveInterfaces.${n}.gateway != null) interfaceNames;

  interfaceConfig = lib.mapAttrs
    (n: iface:
      if iface.mode == "dhcp"
      then { useDHCP = true; }
      else {
        useDHCP = false;
        ipv4.addresses = [{
          address = iface.address;
          prefixLength = iface.prefixLength;
        }];
      })
    effectiveInterfaces;

  # Zero gateway-bearing interfaces: emit no defaultGateway key at all.
  gatewayConfig =
    if gatewayInterfaces == [ ] then
      { }
    else
      let
        ifaceName = builtins.head gatewayInterfaces;
        iface = effectiveInterfaces.${ifaceName};
      in
      {
        defaultGateway = {
          address = iface.gateway;
          interface = ifaceName;
        } // (if iface.metric != null then { metric = iface.metric; } else { });
      };
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
    interfaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          mode = lib.mkOption {
            type = lib.types.enum [ "dhcp" "static" ];
            default = "static";
            description = "Whether this interface uses DHCP or a static address.";
          };
          address = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "The static IPv4 address (mode = static only).";
          };
          prefixLength = lib.mkOption {
            type = lib.types.int;
            default = 24;
            description = "The IPv4 subnet prefix length (mode = static only).";
          };
          gateway = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "The default gateway address reachable via this interface.";
          };
          metric = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "The default-route metric, emitted only when set.";
          };
          nameservers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "List of DNS nameservers used by this interface.";
          };
        };
      });
      default = { };
      description = "Per-interface network configuration, keyed by interface name.";
    };
  };

  config = {
    assertions = [{
      assertion = builtins.length gatewayInterfaces <= 1;
      message = "cfg.networking: multiple interfaces declare a gateway: "
        + lib.concatStringsSep ", " gatewayInterfaces;
    }];

    # Conditionally configure the networking backend
    networking = lib.mkMerge [
      { hostName = host; }
      (lib.mkIf (netCfg.backend == "networkmanager") {
        networkmanager.enable = true;
      })

      (lib.mkIf (netCfg.backend == "networkd")
        ({
          networkmanager.enable = false;
          useDHCP = false;
          useNetworkd = true;
          nameservers = lib.unique
            (lib.concatMap (n: effectiveInterfaces.${n}.nameservers) interfaceNames);
          interfaces = interfaceConfig;
        } // gatewayConfig))
    ];
  };
}
