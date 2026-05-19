{ config, lib, shared, ... }:

{
  options.cfg.k9s.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable k9s Kubernetes TUI";
  };

  config = lib.mkIf config.cfg.k9s.enable {
    home-manager.users.${shared.username} = {
      programs.k9s.enable = true;
      catppuccin.k9s.enable = true;
    };
  };
}
