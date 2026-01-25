{
  deploy = {
    tags = [ "tail" "server" ];
    targetHost = "10.0.30.79";
  };

  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./../../profiles/server.nix
  ];

  nixpkgs.system = "x86_64-linux";

  cfg = {
    framework.enable = true;
    networking = {
      static = {
        interface = "enp191s0";
        address = "10.0.30.79";
        gateway = "10.0.30.1";
        nameservers = [ "10.0.30.1" "9.9.9.9" ];
      };
    };
    strix-halo.enable = true;
    ai.llama-cpp.enable = true;
  };

}
