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
          setw -g automatic-rename off
          set -g extended-keys always
          set -g extended-keys-format csi-u
          set -g focus-events on

          # Status bar: session name on left, info modules on right
          set -g status-left-length 100
          set -g status-right-length 100
          set -g status-left "#{E:@catppuccin_status_session} "
          set -g status-right "#{E:@catppuccin_status_application} #{E:@catppuccin_status_host}"

          # Tell tmux the outer terminal (Ghostty) supports truecolor, underlines,
          # hyperlinks, strikethrough, and focus events.
          set -as terminal-features ",*:RGB:usstyle:hyperlinks:strikethrough:focus"

          # Allow applications inside tmux to send escape sequences straight to
          # Ghostty. Needed for some of pi's fancy rendering.
          set -g allow-passthrough on

          # Reduce mouse scroll speed in copy mode (default scrolls multiple lines)
          bind -T copy-mode WheelUpPane select-pane \; send-keys -X -N 1 scroll-up
          bind -T copy-mode WheelDownPane select-pane \; send-keys -X -N 1 scroll-down
        '';
      };

      # Catppuccin options must be set BEFORE the plugin loads.
      # programs.tmux.extraConfig is placed after plugin run commands.
      catppuccin.tmux.extraConfig = ''
        # Show window name (#W) instead of pane title (#T)
        # so renames via Prefix+, are visible in the status bar.
        set -g @catppuccin_window_text " #W"
        set -g @catppuccin_window_current_text " #W"
      '';
    };
  };
}
