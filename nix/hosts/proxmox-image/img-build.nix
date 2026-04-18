{ config, pkgs, lib, modulesPath, ... }:
{
  system.build.image = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;
    format = "raw";
    partitionTableType = "efi";
    diskSize = "auto";
    additionalSpace = "512M";
    bootSize = "256M";
  };
}
