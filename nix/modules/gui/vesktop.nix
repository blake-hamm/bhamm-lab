{ config, lib, shared, ... }:

{
  options.cfg.vesktop.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Vesktop";
  };

  config = lib.mkIf config.cfg.vesktop.enable {
    home-manager.users.${shared.username} = {
      programs.vesktop = {
        enable = true;
      };
    };
  };
}
