{ lib
, shared
, ...
}:
{
  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  nixpkgs.config.allowUnfree = true;

  # Set your time zone.
  time.timeZone = "America/Denver";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Nix store/gc cleanup
  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 10d";
  };

  # dbus-broker's ExecReload hangs forever when its unit changes during a
  # release switch: systemd-tmpfiles-resetup remounts /tmp partway through
  # activation and the relaunch never answers (nixpkgs papers over the same
  # symptom with RequiresMountsFor). Activation still succeeds, but
  # switch-to-configuration exits 4 and colmena reports a failed deploy.
  #
  # Defer the change to the reboot that always follows a release bump instead.
  # Verified against switch-to-configuration-ng: X-ReloadIfChanged=false plus
  # X-RestartIfChanged=false puts the unit in units_to_skip, so no action is
  # taken at all (a value of reloadIfChanged=false alone would restart dbus,
  # which nixpkgs deliberately avoids).
  systemd.services.dbus-broker = {
    reloadIfChanged = lib.mkForce false;
    restartIfChanged = lib.mkForce false;
  };

  # Other system config
  security.sudo.wheelNeedsPassword = false;
  system.stateVersion = shared.stateVersion;
}
