{
  system = "x86_64-linux";

  deploy = {
    tags = [ "garage" "server" ];
    targetHost = "10.0.20.21";
  };

  imports = [
    ./hardware-configuration.nix
    ./../../profiles/server.nix
  ];

  cfg = {
    networking = {
      static = {
        interface = "eth0";
        address = "10.0.20.21";
        gateway = "10.0.20.2";
        nameservers = [ "10.0.9.2" ];
      };
    };
  };

  # Hand off network control from cloud-init to NixOS networkd
  services.cloud-init.network.enable = false;
}
