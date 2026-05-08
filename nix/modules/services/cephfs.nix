{ config, lib, pkgs, ... }:

let
  cfg = config.cfg.cephfs;
in
{
  options.cfg.cephfs.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable CephFS mounts for bhamm-sports archive";
  };

  config = lib.mkIf cfg.enable {
    # Ceph fuse client
    environment.systemPackages = [ pkgs.ceph-client ];

    # Create mount point
    systemd.tmpfiles.rules = [
      "d /mnt/bhamm-sports 0755 bhamm users -"
    ];

    # Ceph config and keyring from sops secrets
    sops.secrets.cephfs_conf = {
      key = "vault_secrets/core/cephfs/ceph_conf";
      mode = "0644";
    };

    sops.secrets.cephfs_keyring = {
      key = "vault_secrets/core/cephfs/client_keyring";
      mode = "0600";
    };

    # CephFS mount service
    systemd.services.cephfs-bhamm-sports = {
      description = "CephFS bhamm-sports archive";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "forking";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /mnt/bhamm-sports";
        ExecStart = "${pkgs.ceph-client}/bin/mount.fuse.ceph -o ceph.id=bhamm-sports,ceph.conf=${config.sops.secrets.cephfs_conf.path},ceph.keyring=${config.sops.secrets.cephfs_keyring.path},ceph.client-mountpoint=/bhamm-sports,_netdev,defaults,nonempty -- none /mnt/bhamm-sports";
        ExecStop = "${pkgs.util-linux}/bin/umount /mnt/bhamm-sports";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
}
