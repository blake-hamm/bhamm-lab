{ config, lib, ... }:
{
  config = lib.mkIf config.cfg.cross-compilation.enable {
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  };
}
