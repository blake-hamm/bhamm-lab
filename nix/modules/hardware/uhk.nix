{ config, lib, pkgs, ... }:

{
  options.cfg.uhk.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable UHK keyboard support";
  };

  config = lib.mkIf config.cfg.uhk.enable {
    environment.systemPackages = with pkgs; [
      uhk-agent
    ];
    hardware.keyboard.uhk.enable = true;
  };
}
