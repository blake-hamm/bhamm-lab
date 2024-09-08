{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    uhk-agent
  ];
  hardware.keyboard.uhk.enable = true;
}
