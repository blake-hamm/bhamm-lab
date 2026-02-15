{ config, lib, inputs, shared, ... }:
{
  options.cfg = {
    opencode.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OpenCode AI agent";
    };
  };

  config = lib.mkIf config.cfg.opencode.enable {
    home-manager.users.${shared.username} = {
      programs.opencode = {
        enable = true;
        settings = {
          theme = "opencode";
        };
      };
    };
  };
}
