{
  deploy = {
    tags = [ "orangepi" "remote" "server" ];
    targetHost = "10.0.9.2";
  };

  imports = [
    ./hardware-configuration.nix
    ./../../profiles/server.nix
    ./../../modules/hardware/orangepi-zero-3.nix
  ];

  cfg = {
    aarch64.enable = true;
  };
}
