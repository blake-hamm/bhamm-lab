{ config, lib, pkgs, shared, ... }:

{
  options.cfg.tmux.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable tmux terminal multiplexer";
  };

  config = lib.mkIf config.cfg.tmux.enable {
    environment.systemPackages = [ pkgs.tmux ];

    home-manager.users.${shared.username} = {
      programs.tmux = {
        enable = true;
        prefix = "C-Space";
        baseIndex = 1;
        mouse = true;
        terminal = "tmux-256color";
        extraConfig = ''
          set -g renumber-windows on
          set -g status-right ""
          setw -g automatic-rename off
          set -g extended-keys always
          set -g extended-keys-format csi-u
          set -g focus-events on

          # Catppuccin shows pane title (#T) by default; show window name (#W)
          # so renames via Prefix+, are visible in the status bar.
          set -g @catppuccin_window_text " #W"
          set -g @catppuccin_window_current_text " #W"

          # Tell tmux the outer terminal (Ghostty) supports truecolor, underlines,
          # hyperlinks, strikethrough, and focus events.
          set -as terminal-features ",*:RGB:usstyle:hyperlinks:strikethrough:focus"

          # Force tmux to pass 'dim' (ESC[2m) through even if outer terminfo
          # doesn't declare it. Fixes pi 'thinking' grey text.
          set -sa terminal-overrides ",*:dim=\E[2m"

          # Allow applications inside tmux to send escape sequences straight to
          # Ghostty. Needed for some of pi's fancy rendering.
          set -g allow-passthrough on
        '';
      };
    };
  };
}
