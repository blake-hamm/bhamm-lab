{
  system = "aarch64-linux";

  deploy = {
    tags = [ "pi-display" "sbc" "kiosk" "display" ];
    # TEMPORARY, bench iteration only: the address the board holds on the desk
    # VLAN while it is being brought up. Becomes the static host address
    # 10.0.20.22 when the host is moved onto its real VLAN.
    targetHost = "10.0.9.101";
    # TEMPORARY: the bench sshd still listens on the standard port. The shared
    # core/ssh.nix (which moves sshd to 4185 and drops password auth) is
    # deliberately not imported yet - locking SSH out of a headless SBC needs a
    # physical/PiKVM recovery. This reverts to the default 4185 in the change
    # that imports core/ssh.nix.
    targetPort = 22;
    # Only `root` and `kiosk` exist on this image until the bhamm user from
    # core/user.nix lands, so deploy as root rather than the shared username.
    targetUser = "root";
  };

  imports = [
    ./hardware.nix
    ./config.nix
  ];
}
