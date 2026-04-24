{ config, lib, inputs, shared, pkgs, ... }:
let
  piNpm = pkgs.writeShellScript "pi-npm" ''
    export NPM_CONFIG_PREFIX="${"$"}{HOME}/.pi/npm-global"
    mkdir -p "${"$"}{NPM_CONFIG_PREFIX}/lib"
    exec ${pkgs.nodejs}/bin/npm "$@"
  '';
in
{
  options.cfg.pi.enable = lib.mkEnableOption "pi coding agent";

  config = lib.mkIf config.cfg.pi.enable {
    # Expose Kimi API key via sops-nix
    sops.secrets.kimi_api_key = {
      key = "vault_secrets/external/kimi/pi-framework";
      owner = shared.username;
    };

    home-manager.users.${shared.username} = {
      home.packages = [
        inputs.llm-agents.packages.${pkgs.system}.pi
        pkgs.nodejs # pi needs npm to resolve packages
        pkgs.ffmpeg # pi-web-access video frame extraction
        pkgs.yt-dlp # pi-web-access YouTube stream URLs
      ];

      # Pi auth: credentials for providers
      # The !command syntax is evaluated by pi at runtime and cached for the process lifetime
      home.file.".pi/agent/auth.json" = {
        force = true;
        text = builtins.toJSON {
          "kimi-coding" = {
            type = "api_key";
            key = "!cat ${config.sops.secrets.kimi_api_key.path}";
          };
        };
      };

      # Pi themes
      home.file.".pi/agent/themes/catppuccin-mocha.json" = {
        force = true;
        source = ./catppuccin-mocha.json;
      };

      # Pi web search settings: sane defaults for pi-web-access
      # Note: YouTube and local video analysis are disabled because they require
      # Gemini API/Web access. With only Kimi credentials available, these features
      # would fail. Web search still works via Exa MCP (zero-config) and Perplexity.
      home.file.".pi/web-search.json" = {
        force = true;
        text = builtins.toJSON {
          provider = "auto";
          workflow = "summary-review";
          curatorTimeoutSeconds = 20;
          githubClone = {
            enabled = true;
            maxRepoSizeMB = 350;
            cloneTimeoutSeconds = 30;
            clonePath = "/tmp/pi-github-repos";
          };
          youtube = {
            enabled = false;
          };
          video = {
            enabled = false;
          };
          shortcuts = {
            curate = "ctrl+shift+s";
            activity = "ctrl+shift+w";
          };
        };
      };

      # Global AGENTS.md: Karpathy principles + caveman-lite + delegation hints
      home.file.".pi/agent/AGENTS.md" = {
        force = true;
        source = ./agents.md;
      };

      # Global skills
      home.file.".pi/agent/skills/council/SKILL.md" = {
        force = true;
        source = ./skills/council/SKILL.md;
      };
      home.file.".pi/agent/skills/interview/SKILL.md" = {
        force = true;
        source = ./skills/interview/SKILL.md;
      };

      # Custom subagents
      home.file.".pi/agent/agents/architect.md" = {
        force = true;
        source = ./agents/architect.md;
      };
      home.file.".pi/agent/agents/product.md" = {
        force = true;
        source = ./agents/product.md;
      };

      # Pi caveman: default to lite mode
      home.file.".pi/agent/caveman.json" = {
        force = true;
        text = builtins.toJSON {
          defaultLevel = "full";
          showStatus = true;
        };
      };

      # Pi settings: defaults and behavior
      home.file.".pi/agent/settings.json" = {
        force = true;
        text = builtins.toJSON {
          defaultProvider = "kimi-coding";
          defaultModel = "kimi-for-coding";
          theme = "catppuccin-mocha";
          defaultThinkingLevel = "medium";
          quietStartup = true;
          collapseChangelog = true;
          enableInstallTelemetry = false;
          enableSkillCommands = true;

          compaction = {
            enabled = true;
            reserveTokens = 16384;
            keepRecentTokens = 20000;
          };

          retry = {
            enabled = true;
            maxRetries = 3;
            baseDelayMs = 2000;
            maxDelayMs = 60000;
          };

          steeringMode = "one-at-a-time";
          followUpMode = "one-at-a-time";
          transport = "websocket";

          terminal = {
            showImages = true;
            imageWidthCells = 60;
            clearOnShrink = false;
          };

          images = {
            autoResize = true;
            blockImages = false;
          };

          npmCommand = [ "${piNpm}" ];
          packages = [
            "npm:pi-web-access"
            "npm:pi-subagents"
            "npm:pi-rewind"
            "git:github.com/jonjonrankin/pi-caveman"
            "npm:@devkade/pi-plan"
          ];

          subagents = {
            agentOverrides = {
              scout = {
                model = "kimi-coding/kimi-for-coding";
                thinking = "minimal";
              };
              planner = {
                model = "kimi-coding/kimi-for-coding";
              };
              worker = {
                model = "kimi-coding/kimi-for-coding";
              };
              reviewer = {
                model = "kimi-coding/kimi-for-coding";
              };
              context-builder = {
                model = "kimi-coding/kimi-for-coding";
              };
              researcher = {
                model = "kimi-coding/kimi-for-coding";
              };
              delegate = {
                model = "kimi-coding/kimi-for-coding";
                thinking = "minimal";
              };
              oracle = {
                model = "kimi-coding/kimi-for-coding";
              };
              oracle-executor = {
                model = "kimi-coding/kimi-for-coding";
              };
            };
          };
        };
      };
    };
  };
}
