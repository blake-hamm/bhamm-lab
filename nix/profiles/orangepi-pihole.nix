{ config, lib, ... }:
{
  imports = [
    ./sbc.nix
  ];

  # SOPS secrets for Keepalived authentication (shared across primary/backup)
  sops.secrets.keepalived_auth_pass = {
    sopsFile = ../secrets.yaml;
    key = "keepalived_auth_pass";
    restartUnits = [ "keepalived.service" ];
  };

  sops.templates."keepalived-env".content = ''
    KEEPALIVED_AUTH_PASS=${config.sops.placeholder.keepalived_auth_pass}
  '';

  # SOPS secret for NUT UPS password
  sops.secrets.nut_password = {
    sopsFile = ../secrets.yaml;
    key = "nut_password";
    restartUnits = [ "upsdrv.service" "upsd.service" "upsmon.service" ];
  };
}
