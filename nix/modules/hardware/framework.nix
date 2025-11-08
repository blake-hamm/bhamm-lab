{ config, lib, ... }:

{
  config = lib.mkIf config.cfg.framework.enable {
    services.fwupd.enable = true;
  };
}
