{
  image.type = "sd-image";

  deploy = {
    tags = [ "orange-pi" "server" "arm" ];
    targetHost = "10.0.9.2";
  };

  cfg = {
    boot.backend = "extlinux";
    boot.supportedFilesystems = { zfs = false; };
    networking.static = {
      address = "10.0.9.2";
      prefixLength = 24;
      gateway = "10.0.0.1";
      interface = "eth0";
      nameservers = [ "10.0.0.1" "9.9.9.9" ];
    };
  };

  imports = [
    ./hardware-configuration.nix
    ./../../profiles/server.nix
  ];

  nixpkgs.system = "aarch64-linux";
  nixpkgs.config.allowBroken = true;
}
