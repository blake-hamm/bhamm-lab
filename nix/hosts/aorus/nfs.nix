{
  fileSystems."/export/zpool_ssd" = {
    device = "/mnt/zpool_ssd";
    options = [ "bind" ];
  };
  networking.firewall.allowedTCPPorts = [ 2049 ];
  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /export           192.168.69.0/24(rw,fsid=0,no_subtree_check)
    /export/zpool_ssd 192.168.69.0/24(rw,sync,no_subtree_check,no_root_squash)
  '';
}
