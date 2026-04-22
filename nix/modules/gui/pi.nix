{ config, lib, inputs, shared, pkgs, ... }:
{
  options.cfg.pi.enable = lib.mkEnableOption "pi coding agent";

  config = lib.mkIf config.cfg.pi.enable {
    # Expose Kimi API key via sops-nix
    sops.secrets.kimi_api_key = {
      key = "vault_secrets/external/kimi/pi-framework";
      owner = shared.username;
    };

    home-manager.users.${shared.username} = {
      home.packages = [ inputs.llm-agents.packages.${pkgs.system}.pi ];

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

      # Pi settings: default model and behavior
      home.file.".pi/agent/settings.json" = {
        force = true;
        text = builtins.toJSON {
          model = "kimi-for-coding/k2p6";
        };
      };
    };
  };
}
