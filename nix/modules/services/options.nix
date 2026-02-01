{ lib, ... }:

{
  options.cfg = {
    docker.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Docker support";
    };
    docker.rootless.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable rootless Docker support";
    };
    virtualization.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable virtualization tools";
    };
    samba.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Samba shares";
    };
    precommit.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable pre-commit hooks";
    };
    backups.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable backups";
    };
    pihole.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Pi-hole DNS server";
    };
  };
}
