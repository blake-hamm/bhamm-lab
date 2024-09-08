{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    tree
    htop
    kitty
    jq
  ];
}
