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

  nixpkgs.system = "x86_64-linux";

  cfg = {
    # Machine-specific settings
    framework.enable = true;
    wireguard.enable = true;
  };
}
