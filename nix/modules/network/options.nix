{ lib, ... }:

{
  options.cfg = {
    # Networking
    networking.externalInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "The primary external network interface.";
    };
    vpn.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable VPN";
    };
  };
}
