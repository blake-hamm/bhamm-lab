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
        package = inputs.opencode.packages.${pkgs.system}.default;
        settings = {
          model = "kimi-for-coding/k2p6";
          default_agent = "orchestrator";
          mcp = {
            github = {
              enabled = false;
              type = "remote";
              url = "https://api.githubcopilot.com/mcp/";
            };
          };
          plugin = [
            "oh-my-opencode-slim@v0.9.12"
          ];
          provider = {
            "kimi-for-coding" = {
              name = "Kimi For Coding";
              npm = "@ai-sdk/anthropic";
              options = {
                baseURL = "https://api.kimi.com/coding/v1";
              };
              models = {
                k2p6 = {
                  name = "Kimi K2.6";
                  reasoning = true;
                  attachment = false;
                  limit = {
                    context = 262144;
                    output = 32768;
                  };
                  modalities = {
                    input = [ "text" "image" "video" ];
                    output = [ "text" ];
                  };
                  options = {
                    interleaved = {
                      field = "reasoning_content";
                    };
                    thinking = {
                      type = "enabled";
                      budgetTokens = 32000;
                    };
                  };
                };
              };
            };
          };
        };
      };

      xdg.configFile."opencode/oh-my-opencode-slim.json".text = builtins.toJSON {
        preset = "kimi";
        presets = {
          kimi = {
            orchestrator = { model = "kimi-for-coding/k2p6"; variant = "high"; skills = [ "*" ]; mcps = [ "*" ]; };
            oracle = { model = "kimi-for-coding/k2p6"; variant = "high"; skills = [ ]; mcps = [ ]; };
            librarian = { model = "kimi-for-coding/k2p6"; variant = "low"; skills = [ ]; mcps = [ "websearch" "context7" "grep_app" ]; };
            explorer = { model = "kimi-for-coding/k2p6"; variant = "low"; skills = [ ]; mcps = [ ]; };
            designer = { model = "kimi-for-coding/k2p6"; variant = "medium"; skills = [ "agent-browser" ]; mcps = [ ]; };
            fixer = { model = "kimi-for-coding/k2p6"; variant = "low"; skills = [ ]; mcps = [ ]; };
            council = { model = "kimi-for-coding/k2p6"; variant = "med"; skills = [ ]; mcps = [ ]; };
            councillor = { model = "kimi-for-coding/k2p6"; variant = "low"; skills = [ ]; mcps = [ ]; };
            council-master = { model = "kimi-for-coding/k2p6"; variant = "low"; skills = [ ]; mcps = [ ]; };
          };
        };
      };

      xdg.configFile."opencode/tui.json".text = builtins.toJSON {
        theme = "catppuccin";
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
