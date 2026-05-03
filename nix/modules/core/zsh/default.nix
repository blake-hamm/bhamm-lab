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

        shellAliases = {
          ll = "ls -al";
        };

        initContent = ''
          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
          source ~/.config/p10k.zsh
        '';
      };

      xdg.configFile."p10k.zsh".source = ./p10k.zsh;
    };
  };
}
