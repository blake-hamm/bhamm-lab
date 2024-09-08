{ inputs, username, pkgs, ... }:
{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable and configure the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages = [ pkgs.gnome-tour ];

  # Disable services
  services.xserver.excludePackages = [ pkgs.xterm ];

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Home manager config
  home-manager.users.${username} = {
    imports = [ inputs.catppuccin.homeManagerModules.catppuccin ];
    gtk = {
      enable = true;
      catppuccin.enable = true;
      catppuccin.cursor.enable = true;
    };
    dconf = {
      enable = true;
      settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
    };
  };
}
