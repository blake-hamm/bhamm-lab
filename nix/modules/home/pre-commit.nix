{ inputs, username, pkgs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      pre-commit
      rustup
      gcc
    ];
  };
}
