{ host, ... }:
{
  networking.hostName = "${host}";
  networking.networkmanager.enable = true;
}
