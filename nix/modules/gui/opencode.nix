{ config, lib, inputs, shared, pkgs, pkgs-unstable, ... }:
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
          theme = "catppuccin";
          mcp = {
            github = {
              enabled = false;
              type = "remote";
              url = "https://api.githubcopilot.com/mcp/";
            };
          };
        };
      };

      xdg.configFile."opencode/skills/caveman/SKILL.md".source =
        let
          cavemanRepo = pkgs.fetchFromGitHub {
            owner = "JuliusBrussee";
            repo = "caveman";
            rev = "v1.5.1";
            hash = "sha256-gDPgQx1TIhGrJ2EVvEoDY+4MXdlI79zdcx6pL5nMEG4=";
          };
        in
        "${cavemanRepo}/caveman/SKILL.md";
    };
  };
}
