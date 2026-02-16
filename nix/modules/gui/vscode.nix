{ config, lib, inputs, shared, pkgs-unstable, ... }:

{
  config = lib.mkIf config.cfg.vscode.enable {
    home-manager.users.${shared.username} = {
      programs.vscode = {
        enable = true;
        package = pkgs-unstable.vscodium;
        profiles.default = {
          extensions = with pkgs-unstable.vscode-extensions; [
            ms-python.python
            ms-python.isort
            ms-python.black-formatter
            jnoortheen.nix-ide
            hashicorp.terraform
            rooveterinaryinc.roo-cline
            bierner.markdown-mermaid
            budparr.language-hugo-vscode
            ms-toolsai.jupyter
            streetsidesoftware.code-spell-checker
            sst-dev.opencode
            # kilocode.kilo-code
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

            # Roo
            "roo-cline.apiRequestTimeout" = 1800;
            "roo-cline.codeIndex.embeddingBatchSize" = 200;
          };
        };
      };
    };
  };
}
