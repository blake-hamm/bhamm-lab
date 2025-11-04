{ config, host, ... }:
{
  networking.hostName = "${host}";
  networking.networkmanager.enable = true;
  networking.nat = {
    enable = true;
    externalInterface = config.cfg.networking.externalInterface;
  };
}
