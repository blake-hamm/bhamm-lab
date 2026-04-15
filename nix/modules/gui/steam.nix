{ config, lib, ... }:

{
  options.cfg.steam.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Steam";
  };

  config = lib.mkIf config.cfg.steam.enable {
    programs.steam = {
      enable = true;
      # remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
    };
  };
}
