{
  system = "aarch64-linux";

  deploy = {
    tags = [ "orangepi" "sbc" "server" ];
    targetHost = "10.0.9.2";
  };

  imports = [
    ./hardware.nix
    ./../../profiles/sbc.nix
  ];

  cfg = {
    orangepi-zero3.enable = true;
    # pihole.enable = true;  # Phase 3 - module not implemented yet
    networking = {
      backend = "networkd";
      static = {
        interface = "end0";
        address = "10.0.9.2";
        gateway = "10.0.9.1";
        nameservers = [ "10.0.9.1" "9.9.9.9" ];
      };
    };
  };
}
