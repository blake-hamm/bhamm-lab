{
  networking.firewall.allowedTCPPorts = [ 2049 ];
  fileSystems."/mnt/storage" = {
    device = "192.168.69.12:/mnt/storage";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };
}
