{ lib, pkgs, ... }:
let
  bootloaderPackage = pkgs.ubootOrangePiZero3;
in
{
  imports = [
    ../../profiles/sbc.nix
    ./config.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

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
