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
    strix-halo.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Strix Halo specific settings";
    };
    cross-compilation.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable cross-compilation support";
    };
  };
}
