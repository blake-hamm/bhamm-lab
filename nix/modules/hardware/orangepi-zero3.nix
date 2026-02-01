{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.cfg.orangepi-zero3.enable {
    # Force aarch64 platform
    nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";

    # Disable all standard boot loaders - Orange Pi uses U-Boot from SD card
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
    boot.loader.grub.enable = lib.mkForce false;

    # Use latest kernel for H618 support
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

    # Disable ZFS (causes build issues on aarch64)
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

    # H618-specific kernel modules if needed
    boot.initrd.availableKernelModules = [
      "usbhid"
      "usb_storage"
    ];
  };
}
