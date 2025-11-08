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
  };
}
