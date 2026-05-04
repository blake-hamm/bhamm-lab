{ config, lib, pkgs, shared, ... }:

{
  imports = [
    ./starship.nix
  ];

  options.cfg.zsh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Zsh";
    };
    starship.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Starship prompt (disabled by default for servers)";
    };
  };

  config = lib.mkIf config.cfg.zsh.enable {
    # Set zsh as the login shell for the user
    users.users.${shared.username}.shell = pkgs.zsh;

    # Enable system-wide zsh completions
    programs.zsh.enable = true;

    home-manager.users.${shared.username} = {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion = {
          enable = true;
          highlight = "fg=242";
        };
        syntaxHighlighting.enable = true;

        history = {
          size = 100000;
          save = 100000;
          ignoreDups = true;
          ignoreSpace = true;
          share = true;
        };

        shellAliases = {
          ll = "ls -al";
          nd = "nix develop --command zsh";
          k9s = "TERM=xterm-256color k9s";
        };

        initContent = lib.mkMerge [
          ''
            setopt appendhistory
            setopt incappendhistory
            setopt histreduceblanks
            setopt histverify
            setopt no_nomatch
            setopt interactivecomments

            zstyle ':completion:*' use-cache on
            zstyle ':completion:*' cache-path ~/.zsh/cache
            zstyle ':completion:*' menu select
            zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
            zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %d --%f'
            zstyle ':completion:*' group-name ""
          ''
        ];
      };

      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
      };

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };


    };
  };
}
