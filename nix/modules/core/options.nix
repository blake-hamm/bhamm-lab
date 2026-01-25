{ lib, ... }:
{
  options.cfg = {
    boot.backend = lib.mkOption {
      type = lib.types.str;
      default = "systemd-boot";
      description = "The bootloader backend to use";
    };
    boot.supportedFilesystems = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { lvm = true; xfs = true; };
      description = "The supported filesystems";
    };
  };
}
