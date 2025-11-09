{ config, lib, pkgs, shared, ... }:

{
  config = lib.mkIf config.cfg.wireguard.enable {
    home-manager.users.${shared.username} = {
      home.packages = with pkgs; [
        wireguard-tools
      ];
    };
  };
}
