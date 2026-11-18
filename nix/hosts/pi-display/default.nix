{
  system = "aarch64-linux";

  deploy = {
    tags = [ "pi-display" "sbc" "kiosk" "display" ];
    # TEMPORARY, bench iteration only: the address the board holds on the desk
    # VLAN while it is being brought up. Becomes the static host address
    # 10.0.20.22 when the host is moved onto its real VLAN.
    targetHost = "10.0.9.101";
    # TEMPORARY: the running system still has sshd on 22 as root, and colmena
    # resolves the closure-push target from THIS evaluated port (it ignores
    # NIX_SSHOPTS), so pointing at 4185 here fails before activation can switch
    # sshd. Flips to 4185 / bhamm in the next commit, once this generation is
    # installed and key auth is verified.
    targetPort = 22;
    targetUser = "root";
  };

  imports = [
    ./hardware.nix
    ./config.nix
  ];
}
