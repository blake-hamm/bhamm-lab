{ config, lib, inputs, shared, pkgs, ... }:

let
  cfg = config.cfg.backups;
  user = shared.username;
in
{
  options.cfg.backups = {
    enable = lib.mkEnableOption "backups";
    target = lib.mkOption {
      type = lib.types.enum [ "local" "rgw" ];
      default = "local";
      description = "Backup target. 'local' uses borgmatic to a local repo. 'rgw' uses restic to Ceph RGW.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Local borgmatic target
    (lib.mkIf (cfg.target == "local") {
      home-manager.users.${user} = {
        programs.borgmatic = {
          enable = true;
          backups = {
            userdata = {
              location = {
                sourceDirectories = [
                  "/home/${user}/"
                ];
                repositories = [{
                  path = "/home/${user}/backups/borgmatic/userdata";
                  label = "local";
                }];
                extraConfig = {
                  patterns = [
                    "- home/${user}/backups"
                    "- home/${user}/Downloads"
                  ];
                };
              };
              retention = {
                keepDaily = 7;
                keepWeekly = 4;
                keepMonthly = 6;
              };
            };
          };
        };
        home.packages = with pkgs; [ borgbackup ];
      };

      systemd.timers.borgmatic = {
        timerConfig = {
          OnBootSec = "5s";
          OnUnitActiveSec = "2h";
          Persistent = true;
          Unit = "borgmatic.service";
        };
        after = [ "timers.target" ];
      };

      systemd.services.borgmatic = {
        path = with pkgs; [ borgmatic ];
        script = ''
          borgmatic init -e none --verbosity 1 --make-parent-dirs
          borgmatic create --verbosity 1 --list --stats
        '';
        serviceConfig = {
          Type = "oneshot";
          User = "${user}";
        };
      };
    })

    # RGW restic target
    (lib.mkIf (cfg.target == "rgw") {
      sops.secrets.rgw_access_key = {
        key = "init/ceph/ceph-external-secret/s3_access_key";
      };
      sops.secrets.rgw_secret_key = {
        key = "init/ceph/ceph-external-secret/s3_secret_key";
      };
      sops.secrets.restic_password = {
        key = "vault_secrets/core/backups/restic_password";
      };

      sops.templates."restic-rgw-env" = {
        content = ''
          AWS_ACCESS_KEY_ID=${config.sops.placeholder.rgw_access_key}
          AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.rgw_secret_key}
        '';
      };

      services.restic.backups.framework = {
        initialize = true;
        repository = "s3:https://rgw.bhamm-lab.com/framework-backup";
        passwordFile = config.sops.secrets.restic_password.path;
        environmentFile = config.sops.templates."restic-rgw-env".path;
        paths = [
          "/home/${user}"
          "/mnt/bhamm"
        ];
        exclude = [
          "/home/${user}/.cache"
          "/home/${user}/Downloads"
          "/home/${user}/.local/share/Steam/steamapps/common"
          "/home/${user}/.local/share/docker"
          "/home/${user}/.conda"
          "/home/${user}/backups"
        ];
        pruneOpts = [
          "--keep-last 5"
          "--keep-daily 2"
          "--keep-weekly 1"
          "--keep-monthly 1"
          "--keep-yearly 1"
        ];
        checkOpts = [ "--read-data-subset=10%" ];
        timerConfig = {
          OnCalendar = "04:00";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
        extraBackupArgs = [ "--tag auto" ];
      };

      home-manager.users.${user}.home.packages = with pkgs; [ restic ];

      # Enable progress output in systemd journal (non-TTY)
      systemd.services.restic-backups-framework.serviceConfig.Environment = [ "RESTIC_PROGRESS_FPS=0.05" ];
    })
  ]);
}
