{
  deploy = {
    tags = [ "framework" "local" "desktop" ];
    targetHost = "localhost";
    allowLocalDeployment = true;
  };

  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./../../profiles/desktop.nix
  ];

  cfg = {
    # Machine-specific settings
    framework.enable = true;
    wireguard.enable = true;
  };

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
}
