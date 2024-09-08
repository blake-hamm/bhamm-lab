{ inputs, username, pkgs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${username} = {
    programs.borgmatic = {
      enable = true;
      backups = {
        userdata = {
          location = {
            sourceDirectories = [
              "/home/${username}/"
            ];
            repositories = [{
              "path" = "/home/${username}/backups/borgmatic/userdata";
              "label" = "local";
            }];
            extraConfig = {
              "patterns" = [
                "- home/${username}/backups"
                "- home/${username}/Downloads"
              ];
            };
            # Below us available in unstable branch
            # patterns = [
            #     "- home/${username}/backups"
            # ];
          };
          retention = {
            keepDaily = 7;
            keepWeekly = 4;
            keepMonthly = 6;
          };
          # hooks.extraConfig = {};
          # storage.encryptionPasscode = {};
        };
      };
    };
    home.packages = with pkgs; [
      borgbackup
    ];
  };

  # TODO: Contribute https://nixos.wiki/wiki/Nixpkgs/Create_and_debug_packages#Adding_custom_libraries_and_dependencies_to_a_package
  #  and use custom fork input
  # borgmatic init --encryption repokey
  # borgmatic create --verbosity 1 --list --stats

  # Create systemd timer
  systemd = {
    timers."borgmatic" = {
      timerConfig = {
        OnBootSec = "5s";
        OnUnitActiveSec = "2h";
        Persistent = true;
        Unit = "borgmatic.service";
      };
      after = [ "timers.target" ];
    };
    services."borgmatic" = {
      path = with pkgs; [ borgmatic ];
      script = ''
        borgmatic init -e none --verbosity 1 --make-parent-dirs
        borgmatic create --verbosity 1 --list --stats
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "${username}";
      };
    };
  };

  # TODO: Orchestrate with argo workflows
  # TODO: Rsync to remote machine
}
