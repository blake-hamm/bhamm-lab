{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./../../modules/profiles/desktop.nix
  ];

  cfg = {
    # Machine-specific settings
    framework.enable = true;
    networking.externalInterface = "wlp1s0";
  };
}
