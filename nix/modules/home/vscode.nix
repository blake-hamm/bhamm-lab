{ inputs, username, pkgs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${username} = {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        ms-python.isort
        ms-python.black-formatter
        jnoortheen.nix-ide
        catppuccin.catppuccin-vsc
        catppuccin.catppuccin-vsc-icons
        # dracula-theme.theme-dracula
        # vscodevim.vim
        # yzhang.markdown-all-in-one
      ];
      userSettings = {
        # Settings
        "explorer.confirmDelete" = false;
        "editor.tabSize" = 2;
        "editor.insertSpaces" = true;
        "editor.detectIndentation" = false;

        # Theme
        "window.zoomLevel" = -3;
        "workbench.colorTheme" = "Catppuccin Mocha";
        "workbench.iconTheme" = "catppuccin-mocha";
        "catppuccin.accentColor" = "sapphire";
      };
    };
  };
}
