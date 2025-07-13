{ inputs, username, pkgs, config, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  nixpkgs.config.permittedInsecurePackages = [
    "electron-19.1.9" # Required for etcher
  ];
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      drawio
      dbeaver-bin
      virt-manager
      obs-studio
      shotcut
      # signal-desktop
      # gnome-network-displays
      # steam
      # etcher
      # kubectl
      # kubernetes-helm
      # argocd
    ];
  };
}
