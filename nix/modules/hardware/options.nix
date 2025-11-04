{ lib, ... }:

{
  options.cfg = {
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
  };
}
