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

    # Optional: Export catppuccin colors for use in other modules
    environment.variables = {
      CATPPUCCIN_FLAVOR = catppuccinFlavor;
    };

    # Home-manager Catppuccin theming (desktop only)
    home-manager.users.${shared.username} = {
      catppuccin.enable = true;
      catppuccin.flavor = catppuccinFlavor;
    };
  };
}
