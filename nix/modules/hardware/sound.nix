{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.cfg.gnome.enable {
    # Enable sound with pipewire.
    # sound.enable = true;
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}
