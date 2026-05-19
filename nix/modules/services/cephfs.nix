{ config, lib, pkgs, ... }:

let
  cfg = config.cfg.cephfs;
  mountPoint = "/mnt/bhamm";
  keyFile = "/run/ceph/bhamm.key";
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

    # Ceph client tools (still useful for debugging)
    environment.systemPackages = [ pkgs.ceph-client ];

    # Ensure mount point and key directory exist
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 bhamm users -"
      "d /run/ceph 0755 root root -"
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

    # Extract raw key from keyring for kernel client at activation time
    system.activationScripts.cephfs-bhamm-key = {
      text = ''
        mkdir -p /run/ceph
        ${pkgs.gnugrep}/bin/grep -oP 'key\s*=\s*\K[^\s]+' ${config.sops.secrets.cephfs_keyring.path} > ${keyFile}
        chmod 600 ${keyFile}
      '';
      deps = [ "setupSecrets" ];
    };

    # Kernel CephFS mount unit (started on-demand by automount)
    systemd.mounts = [
      {
        what = "10.0.20.11:6789,10.0.20.12:6789,10.0.20.13:6789:/bhamm";
        where = mountPoint;
        type = "ceph";
        options = "name=bhamm,conf=${config.sops.secrets.cephfs_conf.path},secretfile=${keyFile},_netdev";
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

    # Pre-sleep: cleanly unmount before network goes down
    systemd.services.cephfs-bhamm-sleep = {
      description = "Stop CephFS mount before sleep";
      before = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${pkgs.systemd}/bin/systemctl stop mnt-bhamm.mount";
      };
    };
  };
}
