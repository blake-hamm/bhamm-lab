{ pkgs, lib, ... }:
{
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
