{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.cfg.uhk.enable {
    environment.systemPackages = with pkgs; [
      uhk-agent
    ];
    hardware.keyboard.uhk.enable = true;
  };
}
