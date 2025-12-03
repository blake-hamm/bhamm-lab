{ config, lib, shared, ... }:

{
  config = lib.mkIf config.cfg.vesktop.enable {
    home-manager.users.${shared.username} = {
      programs.vesktop = {
        enable = true;
      };
    };
  };
}
