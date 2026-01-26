{
  deploy = {
    tags = [ "orangepi" "remote" "server" ];
    targetHost = "10.0.9.2";
  };

  imports = [
    ./hardware-configuration.nix
    ./../../profiles/server.nix
  ];

  cfg = {
    aarch64.enable = true;
  };
}
