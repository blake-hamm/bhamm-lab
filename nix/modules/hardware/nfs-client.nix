{
  networking.firewall.allowedTCPPorts = [ 2049 ];
  fileSystems."/mnt/zpool_ssd" = {
    device = "192.168.69.12:/zpool_ssd";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };
}
