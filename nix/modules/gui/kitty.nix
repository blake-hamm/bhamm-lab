{ config, lib, inputs, shared, ... }:

{
  options.cfg.kitty.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Kitty terminal";
  };

  config = lib.mkIf config.cfg.kitty.enable {
    home-manager.users.${shared.username} = {
      programs.kitty = {
        enable = true;
        settings = {
          scrollback_lines = 10000;
          enable_audio_bell = false;
          font_size = 8;
        };
      };
    };
  };
}
