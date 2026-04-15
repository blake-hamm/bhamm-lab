{ config, lib, ... }:

{
  options.cfg.framework.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Framework specific settings";
  };

  config = lib.mkIf config.cfg.framework.enable {
    services.fwupd.enable = true;
  };
}
