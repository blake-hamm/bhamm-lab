{
  system = "aarch64-linux";

  deploy = {
    tags = [ "orangepi" "sbc" "server" ];
    targetHost = "10.0.9.2";
  };

  imports = [
    ./hardware.nix
    ./config.nix
    ./../../profiles/sbc.nix
  ];
}
