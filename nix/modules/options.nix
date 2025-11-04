{ lib, ... }:

{
  options.cfg = {
    # Desktop Environment
    gnome.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GNOME desktop environment";
    };

    # Features
    docker.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Docker support";
    };
    virtualization.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable virtualization tools";
    };
    steam.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Steam";
    };
    signal.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Signal";
    };
    samba.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Samba shares";
    };
    kitty.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Kitty terminal";
    };
    vscode.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable VS Codium";
    };
    precommit.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable pre-commit hooks";
    };
    backups.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable backups";
    };
    vpn.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable VPN";
    };

    # Hardware
    framework.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Framework specific settings";
    };
    uhk.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable UHK keyboard support";
    };

    # Networking
    networking.externalInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "The primary external network interface.";
    };
  };
}
