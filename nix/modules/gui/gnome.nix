{ config, lib, inputs, shared, pkgs, ... }:

{
  config = lib.mkIf config.cfg.gnome.enable {
    # Enable the X11 windowing system.
    services.xserver.enable = true;

    # Enable and configure the GNOME Desktop Environment.
    services.xserver.displayManager.gdm.enable = true;
    services.xserver.desktopManager.gnome.enable = true;
    environment.gnome.excludePackages = [ pkgs.gnome-tour ];

    # Disable services
    services.xserver.excludePackages = [ pkgs.xterm ];

    # Configure keymap in X11
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };

    # Home manager config
    home-manager.users.${shared.username} = {
      gtk = {
        enable = true;
      };
      dconf = {
        enable = true;
        settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
      };
    };
  };
}
