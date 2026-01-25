{ config, lib, pkgs, ... }:
let
  bootCfg = config.cfg.boot;
in
{
  boot.supportedFilesystems = bootCfg.supportedFilesystems;
  boot.loader.systemd-boot.enable = lib.mkDefault (bootCfg.backend == "systemd-boot");
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault (bootCfg.backend == "systemd-boot");
  boot.loader.generic-extlinux-compatible.enable = lib.mkDefault (bootCfg.backend == "extlinux");
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
