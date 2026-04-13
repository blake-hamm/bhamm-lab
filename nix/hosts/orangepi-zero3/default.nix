{
  system = "aarch64-linux";

  deploy = {
    tags = [ "orangepi" "sbc" "pihole" "server" ];
    targetHost = "10.0.9.3";
  };

  imports = [
    ./hardware.nix
    ./config.nix
    ./../../profiles/orangepi-pihole.nix
  ];
}
