{
  system = "aarch64-linux";

  deploy = {
    tags = [ "orangepi" "sbc" "server" "backup" ];
    targetHost = "10.0.9.4";
  };

  imports = [
    ./hardware.nix
    ./config.nix
    ./../../profiles/orangepi-pihole.nix
  ];
}
