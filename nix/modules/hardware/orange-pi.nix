{ lib
, config
, modulesPath
, pkgs-unstable
, ...
}:
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];
  config = lib.mkIf config.cfg.orange-pi.enable {
    # U-Boot
    sdImage.postBuildCommands = ''
      dd if=${pkgs-unstable.ubootOrangePiZero3}/u-boot-sunxi-with-spl.bin of=$img bs=1024 seek=8 conv=notrunc
    '';
  };
}
