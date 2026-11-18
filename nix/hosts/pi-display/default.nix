{
  system = "aarch64-linux";

  deploy = {
    tags = [ "pi-display" "sbc" "kiosk" "display" ];
    # TEMPORARY, bench iteration only: the address the board holds on the desk
    # VLAN while it is being brought up. Becomes the static host address
    # 10.0.20.22 when the host is moved onto its real VLAN.
    targetHost = "10.0.9.101";
    targetPort = 4185;
    targetUser = "bhamm";
  };

  imports = [
    ./hardware.nix
    ./config.nix
  ];
}
