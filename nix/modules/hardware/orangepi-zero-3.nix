{ lib, config, pkgs, inputs, ... }:

let
  bootloaderPackage = pkgs.ubootOrangePiZero3;
  bootloaderSubpath = "/u-boot-sunxi-with-spl.bin";
  filesystems = pkgs.lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" "ext4" ];
  bootConfig = {
    system.stateVersion = lib.mkDefault "25.11";

    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.grub.enable = false;
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

    # Disable ZFS
    boot.supportedFilesystems = filesystems;
    boot.initrd.supportedFilesystems = filesystems;

    sdImage = {
      compressImage = true;
      postBuildCommands = ''
        # Emplace bootloader to specific place in firmware file
        dd if=${bootloaderPackage}${bootloaderSubpath} of=$img \
          bs=8k seek=1 \
          conv=notrunc # prevent truncation of image
      '';
    };
  };
in
{
  imports = [
    (import "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix")
  ];
  config = bootConfig;
}
