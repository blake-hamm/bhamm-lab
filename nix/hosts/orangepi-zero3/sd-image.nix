{ lib, pkgs, shared, ... }:
let
  # Use Orange Pi Zero 3 u-boot as base
  bootloaderPackage = pkgs.ubootOrangePiZero3;
in
{
  imports = [
    ../../modules/core
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # Hostname
  networking.hostName = "orangepi-zero3";

  # Static IP configuration for colmena deployment
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.nameservers = [ "10.0.9.1" "9.9.9.9" ];
  networking.interfaces.end0 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "10.0.9.2";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = {
    address = "10.0.9.1";
    interface = "end0";
  };

  # Override boot.nix settings - ARM uses U-Boot, not systemd-boot
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # Use latest kernel for H618 support (overrides boot.nix)
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  # Disable ZFS to avoid build issues
  boot.supportedFilesystems = lib.mkForce [
    "btrfs"
    "vfat"
    "f2fs"
    "xfs"
    "ext4"
  ];
  boot.initrd.supportedFilesystems = lib.mkForce [
    "btrfs"
    "vfat"
    "f2fs"
    "xfs"
    "ext4"
  ];

  # SD Image configuration
  sdImage = {
    compressImage = true;
    # Write u-boot to SD card
    postBuildCommands = ''
      dd if=${bootloaderPackage}/u-boot-sunxi-with-spl.bin of=$img \
        bs=1024 seek=8 conv=notrunc
    '';
  };
}
