{
  system = "aarch64-linux";

  deploy = {
    tags = [ "pi-display" "sbc" "kiosk" "display" ];
    # Static address on the metal VLAN. The end0 DHCP lease is a bench-only
    # recovery path, not a deploy target.
    targetHost = "10.0.20.22";
    targetPort = 4185;
    targetUser = "bhamm";
  };

  imports = [
    ./hardware.nix
    ./config.nix
  ];
}
