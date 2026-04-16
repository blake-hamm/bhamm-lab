{ config, lib, pkgs, ... }:

{
  options.cfg.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable PipeWire audio";
  };

  config = lib.mkIf config.cfg.audio.enable {
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
