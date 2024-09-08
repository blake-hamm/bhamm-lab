{ inputs, username, pkgs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${username} = {
    programs.firefox = {
      enable = true;
    };
  };
}
