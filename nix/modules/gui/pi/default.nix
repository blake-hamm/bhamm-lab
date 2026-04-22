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

      # Pi settings: defaults and behavior
      home.file.".pi/agent/settings.json" = {
        force = true;
        text = builtins.toJSON {
          model = "kimi-for-coding/k2p6";
          theme = "catppuccin-mocha";
          defaultThinkingLevel = "high";
          quietStartup = false;
          collapseChangelog = true;
          enableInstallTelemetry = false;

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
          transport = "auto";

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
          ];
        };
      };
    };
  };
}
