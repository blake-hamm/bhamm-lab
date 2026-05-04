{ config, lib, inputs, shared, ... }:

let
  userShell = config.users.users.${shared.username}.shell;
in
{
  options.cfg.ghostty.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Ghostty terminal";
  };

  config = lib.mkIf config.cfg.ghostty.enable {
    home-manager.users.${shared.username} = {
      programs.ghostty = {
        enable = true;
        settings = {
          theme = "catppuccin-mocha";
          font-size = 8;
          scrollback-limit = 10000000;
          command =
            if config.cfg.tmux.enable
            then "tmux new-session -A -s main"
            else lib.getExe userShell;
        };
      };
    };
  };
}
