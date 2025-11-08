{ config, lib, inputs, shared, ... }:

let
  catppuccinFlavor = "mocha";
in
{
  imports = [
    inputs.catppuccin.nixosModules.catppuccin
  ];

  config = lib.mkIf config.cfg.gnome.enable {

    # NixOS-level Catppuccin configuration
    catppuccin = {
      enable = true;
      flavor = catppuccinFlavor;
    };

    home-manager.sharedModules = [
      inputs.catppuccin.homeModules.catppuccin
    ];

    home-manager.users.${shared.username} = {
      catppuccin = {
        enable = true;
        vscode.profiles.default.accent = "sapphire";
      };
    };

    # Optional: Export catppuccin colors for use in other modules
    environment.variables = {
      CATPPUCCIN_FLAVOR = catppuccinFlavor;
    };
  };
}
