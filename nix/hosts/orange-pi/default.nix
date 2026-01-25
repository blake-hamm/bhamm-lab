{
  deploy = {
    tags = [ "orange-pi" "server" "arm" ];
    targetHost = "10.0.9.2";
  };

  imports = [
    ./hardware-configuration.nix
    ./../../profiles/server.nix
  ];

  nixpkgs.system = "aarch64-linux";
}
