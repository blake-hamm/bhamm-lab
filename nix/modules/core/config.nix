{ lib, ... }:

{
  options.cfg = {
    # Profiles
    gnome.enable = lib.mkEnableOption "Enable GNOME desktop environment";

    # Features
    docker.enable = lib.mkEnableOption "Enable Docker support";
    virtualization.enable = lib.mkEnableOption "Enable virtualization tools";
    steam.enable = lib.mkEnableOption "Enable Steam";
    signal.enable = lib.mkEnableOption "Enable Signal";

    # Hardware
    framework.enable = lib.mkEnableOption "Enable Framework laptop specific settings";

    # Networking
    networking.externalInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "The primary external network interface.";
    };
  };
}
