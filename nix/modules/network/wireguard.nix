{ config, lib, pkgs, shared, ... }:

{
  options.cfg.wireguard.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable WireGuard VPN";
  };

  config = lib.mkIf config.cfg.wireguard.enable {
    home-manager.users.${shared.username} = {
      home.packages = with pkgs; [
        wireguard-tools
      ];
    };
  };
}
