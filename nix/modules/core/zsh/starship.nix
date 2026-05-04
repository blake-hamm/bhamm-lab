{ config, lib, shared, ... }:

{
  config = lib.mkIf (config.cfg.zsh.enable && config.cfg.zsh.starship.enable) {
    home-manager.users.${shared.username} = {
      programs.starship = {
        enable = true;
        settings = {
          format = lib.concatStrings [
            "$nix_shell"
            "$directory"
            "$git_branch"
            "$git_status"
            "$fill"
            "$status"
            "$cmd_duration"
            "$jobs"
            "$time"
            "$line_break"
            "$character"
          ];

          fill = {
            symbol = "─";
            style = "surface1";
          };

          directory = {
            truncation_length = 3;
            truncate_to_repo = true;
            fish_style_pwd_dir_length = 2;
            read_only = " ";
            format = "[$path]($style) ";
          };

          git_branch = {
            format = "[$symbol$branch]($style) ";
            symbol = " ";
          };

          git_status = {
            format = "([$all_status$ahead_behind]($style))";
            conflicted = "= ";
            ahead = "⇡$count ";
            behind = "⇣$count ";
            diverged = "⇕ ";
            up_to_date = "";
            untracked = "?$count ";
            stashed = "\$$count ";
            modified = "!$count ";
            staged = "+$count ";
            renamed = "»$count ";
            deleted = "✘$count ";
          };

          nix_shell = {
            format = "[$symbol$state]($style) ";
            symbol = " ";
            impure_msg = "impure";
            pure_msg = "pure";
          };

          status = {
            disabled = false;
            format = "[$symbol$status]($style) ";
            symbol = "✘ ";
            map_symbol = true;
          };

          cmd_duration = {
            min_time = 2000;
            format = "[$duration]($style) ";
          };

          jobs = {
            format = "[$symbol$number]($style) ";
            symbol = "▼ ";
          };

          time = {
            disabled = false;
            format = "[$time]($style) ";
            time_format = "%H:%M:%S";
          };

          character = {
            success_symbol = "[❯](mauve)";
            error_symbol = "[❯](red)";
            vimcmd_symbol = "[❮](green)";
          };
        };
      };
    };
  };
}
