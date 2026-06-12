{ config, lib, pkgs, ... }:

let
  cfg = config.cfg.cephfs;
  mountPoint = "/mnt/bhamm";
in
{
  options.cfg.cephfs.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable on-demand CephFS automount for bhamm directories";
  };

  config = lib.mkIf cfg.enable {
    # Load kernel Ceph module
    boot.kernelModules = [ "ceph" ];

    # ceph-client provides mount.ceph helper which resolves monitors and
    # reads keyrings, so we don't need to extract raw keys ourselves
    environment.systemPackages = [ pkgs.ceph-client ];

    # Local disk cache for CephFS files (persisted across remounts)
    services.cachefilesd = {
      enable = true;
      extraConfig = ''
        brun 10%
        bcull 7%
        bstop 3%
        frun 10%
        fcull 7%
        fstop 3%
      '';
    };

    # Ensure mount point exists
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 bhamm users -"
    ];

    # Ceph config and keyring from sops secrets, placed at standard paths
    # so mount.ceph helper finds them automatically
    sops.secrets.cephfs_conf = {
      key = "vault_secrets/core/cephfs/ceph_conf";
      mode = "0644";
      path = "/etc/ceph/ceph.conf";
    };

    sops.secrets.cephfs_keyring = {
      key = "vault_secrets/core/cephfs/client_keyring";
      mode = "0600";
      path = "/etc/ceph/ceph.client.bhamm.keyring";
    };

    # Kernel CephFS mount unit (started on-demand by automount)
    # mount.ceph helper reads keyring natively — no secretfile/conf needed
    systemd.mounts = [
      {
        what = "10.0.20.11:6789,10.0.20.12:6789,10.0.20.13:6789:/bhamm";
        where = mountPoint;
        type = "ceph";
        options = "name=bhamm,_netdev,fsc,mount_timeout=5,x-systemd.mount-timeout=10s";
      }
    ];

    # Automount: kernel intercepts access and triggers the mount unit
    systemd.automounts = [
      {
        where = mountPoint;
        wantedBy = [ "multi-user.target" ];
        automountConfig = {
          TimeoutIdleSec = "300";
        };
      }
    ];

    # Pre-sleep: stop ceph mount (not autofs) before network goes down
    systemd.services.cephfs-bhamm-sleep = {
      description = "Stop CephFS mount before sleep";
      before = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${pkgs.systemd}/bin/systemctl stop mnt-bhamm.mount";
      };
    };

    # Post-wake: restart automount to recover from autofs pipe errors
    systemd.services.cephfs-bhamm-wake = {
      description = "Restart CephFS automount after wake";
      after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "network-online.target" ];
      wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${pkgs.systemd}/bin/systemctl restart mnt-bhamm.automount";
      };
    };
  };
}
