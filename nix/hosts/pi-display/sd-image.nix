{ lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./config.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # SD image configuration. The firmware partition, config.txt and the
  # generation-kernel layout come from inputs.nixos-raspberrypi.nixosModules.sd-image,
  # which the flake's pi-display-image attribute imports alongside this file -
  # same split as the Orange Pi SD images, minus the u-boot postBuildCommands
  # (the Pi 5 boots firmware-direct, there is no bootloader blob to dd).
  sdImage = {
    compressImage = true;
  };
}
