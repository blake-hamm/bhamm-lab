{ config, lib, pkgs, shared, ... }:

{
  options.cfg.zsh.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Zsh with Powerlevel10k";
  };

  config = lib.mkIf config.cfg.zsh.enable {
    # Set zsh as the login shell for the user
    users.users.${shared.username}.shell = pkgs.zsh;

    # Enable system-wide zsh completions
    programs.zsh.enable = true;

    home-manager.users.${shared.username} = {
      home.packages = with pkgs; [
        zsh-powerlevel10k
      ];

      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
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
        };

        initContent = lib.mkMerge [
          (lib.mkBefore ''
            if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
              source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
            fi
          '')
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
            zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
            zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %d --%f'
            zstyle ':completion:*' group-name ""

            source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
            source ~/.config/p10k.zsh
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

      xdg.configFile."p10k.zsh".source = ./p10k.zsh;
    };
  };
}
