{ config, lib, inputs, username, ... }:

{
  config = lib.mkIf config.cfg.kitty.enable {
    home-manager.users.${username} = {
      programs.kitty = {
        enable = true;
        # catppuccin.enable = true;
        settings = {
          scrollback_lines = 10000;
          enable_audio_bell = false;
          font_size = 8;
          wayland_titlebar_color = "#181825";
        };
      };
    };
  };
}
