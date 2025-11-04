{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./../../modules/profiles/desktop.nix
  ];

  cfg = {
    gnome.enable = true;
    docker.enable = true;
    virtualization.enable = true;
    steam.enable = true;
    framework.enable = true;
    networking.externalInterface = "wlp1s0";
  };
}
