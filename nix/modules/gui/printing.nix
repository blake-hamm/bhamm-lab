{ lib, config, pkgs, ... }:
{
  config = lib.mkIf config.cfg.gnome.enable {

    services.printing = {
      enable = true;
      drivers = [ pkgs.brlaser pkgs.brgenml1lpr pkgs.brgenml1cupswrapper ];
    };

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

  };
}
