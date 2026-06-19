{ config, lib, inputs, shared, pkgs, ... }:
let
  piNpm = pkgs.writeShellScript "pi-npm" ''
    export NPM_CONFIG_PREFIX="${"$"}{HOME}/.pi/npm-global"
    mkdir -p "${"$"}{NPM_CONFIG_PREFIX}/lib"
    exec ${pkgs.nodejs}/bin/npm "$@"
  '';
  kimiKeyPath = config.sops.secrets.kimi_api_key.path;
  opensenseKeyPath = config.sops.secrets.opensense_api_key.path;
  workersAiTokenPath = config.sops.secrets.pi_workers_ai.path;
in
{
  options.cfg.pi.enable = lib.mkEnableOption "pi coding agent";

  config = lib.mkIf config.cfg.pi.enable {
    # Expose Kimi API key via sops-nix
    sops.secrets.kimi_api_key = {
      key = "vault_secrets/external/kimi/pi-framework";
      owner = shared.username;
    };

    sops.secrets.litellm_api_key = {
      key = "vault_secrets/default/litellm/LITELLM_MASTER_KEY";
      owner = shared.username;
    };

    sops.secrets.opensense_api_key = {
      key = "vault_secrets/external/opencode/pi-framework";
      owner = shared.username;
    };

    sops.secrets.pi_workers_ai = {
      key = "vault_secrets/external/cloudflare/pi-workers-ai";
      owner = shared.username;
    };

    home-manager.users.${shared.username} = { config, lib, ... }: {
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
            key = "!cat ${kimiKeyPath}";
          };
          "opencode-go" = {
            type = "api_key";
            key = "!cat ${opensenseKeyPath}";
          };
          "cloudflare-workers-ai" = {
            type = "api_key";
            key = "!cat ${workersAiTokenPath}";
          };
        };
      };

      # LiteLLM dynamic model discovery extension
      home.file.".pi/agent/extensions/litellm-discovery.ts" = {
        force = true;
        source = ./extensions/litellm-discovery.ts;
      };

      # Cloudflare Workers AI baseUrl with hardcoded account ID — avoids needing CLOUDFLARE_ACCOUNT_ID env var
      home.file.".pi/agent/models.json" = {
        force = true;
        text = builtins.toJSON {
          providers = {
            "cloudflare-workers-ai" = {
              baseUrl = "https://api.cloudflare.com/client/v4/accounts/334b75e7892d552ad3ec86277e987ca4/ai/v1";
            };
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
          summaryModel = "opencode-go/deepseek-v4-flash";
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

      # Custom subagents (override builtins to suppress cwd output files)
      home.file.".pi/agent/agents/scout.md" = {
        force = true;
        source = ./agents/scout.md;
      };
      home.file.".pi/agent/agents/planner.md" = {
        force = true;
        source = ./agents/planner.md;
      };
      home.file.".pi/agent/agents/researcher.md" = {
        force = true;
        source = ./agents/researcher.md;
      };
      home.file.".pi/agent/agents/context-builder.md" = {
        force = true;
        source = ./agents/context-builder.md;
      };
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
          defaultLevel = "lite";
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
              worker = {
                model = "kimi-coding/kimi-for-coding";
              };
              reviewer = {
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
