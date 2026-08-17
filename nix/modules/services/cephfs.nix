{ config, lib, pkgs, ... }:

let
  cfg = config.cfg.cephfs;
  mountPoint = "/mnt/bhamm";
  mons = [ "10.0.20.11" "10.0.20.12" "10.0.20.13" ];
  systemctl = "${pkgs.systemd}/bin/systemctl";

  # Probe mons over TCP :6789 (works identically on LAN and VPN).
  # Reachable -> enable automount; unreachable -> tear it down so
  # ${mountPoint} becomes a plain empty dir and stats return instantly.
  checkScript = pkgs.writeShellScript "cephfs-check" ''
    ok=1
    for mon in ${lib.concatStringsSep " " mons}; do
      if timeout 1 ${pkgs.bash}/bin/bash -c "echo >/dev/tcp/$mon/6789" 2>/dev/null; then
        ok=0
        break
      fi
    done

    if [ "$ok" -eq 0 ]; then
      ${systemctl} start cephfs-reachable.service
      ${systemctl} start mnt-bhamm.automount
    else
      # Requires= propagation stops mnt-bhamm.automount
      ${systemctl} stop cephfs-reachable.service
      # Dead cephfs can block a clean unmount; fall back to lazy detach
      timeout 5 ${systemctl} stop mnt-bhamm.mount || \
        ${pkgs.util-linux}/bin/umount -l ${mountPoint} || true
    fi
  '';
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

    # State flag: active while ceph mons are reachable. Started/stopped
    # exclusively by cephfs-check.service.
    systemd.services.cephfs-reachable = {
      description = "CephFS mons reachable (state flag for automount gate)";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
    };

    # Reachability checker: probe mons, open/close the automount gate
    systemd.services.cephfs-check = {
      description = "Check CephFS mon reachability and gate automount";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = checkScript;
      };
    };

    # Periodic re-check to catch network loss; NM dispatcher covers fast
    # reactions on connect/disconnect
    systemd.timers.cephfs-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15s";
        OnUnitActiveSec = "15s";
      };
    };

    # Fire a check immediately on any network connect/disconnect
    networking.networkmanager.dispatcherScripts = lib.mkIf (config.cfg.networking.backend == "networkmanager") [
      {
        type = "basic";
        source = pkgs.writeShellScript "cephfs-dispatcher" ''
          case "$2" in
            up|down|connectivity-change)
              ${systemctl} start --no-block cephfs-check.service
              ;;
          esac
        '';
      }
    ];

    # Automount: kernel intercepts access and triggers the mount unit.
    # Gated on cephfs-reachable: when the gate closes, Requires= propagation
    # stops the automount so no new mount jobs can be triggered.
    # Lifecycle owned by cephfs-check (no wantedBy: booting offline would
    # fail the Requires= and mark the unit failed).
    systemd.automounts = [
      {
        where = mountPoint;
        requires = [ "cephfs-reachable.service" ];
        after = [ "cephfs-reachable.service" ];
        automountConfig = {
          TimeoutIdleSec = "60";
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
        ExecStart = "-${systemctl} stop mnt-bhamm.mount";
      };
    };

    # Post-wake: restart automount to recover from autofs pipe errors
    systemd.services.cephfs-bhamm-wake = {
      description = "Restart CephFS automount after wake";
      after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "network-online.target" ];
      wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${systemctl} restart mnt-bhamm.automount";
      };
    };
  };
}
