{ config, lib, ... }:
{
  imports = [
    ./sbc.nix
  ];

  # Shared NUT config (same UPS model on both systems)
  cfg.nut = {
    enable = true;
    mode = "netserver";
    driver = "usbhid-ups";
    directives = [
      "vendorid = 0764"
      "productid = 0601"
    ];
    listenAddresses = [ "127.0.0.1" ];
    passwordFile = config.sops.secrets.nut_password.path;
  };

  # SOPS secrets for Keepalived authentication (shared across primary/backup)
  sops.secrets.keepalived_auth_pass = {
    key = "vault_secrets/core/orangepi/keepalived_auth_pass";
    restartUnits = [ "keepalived.service" ];
  };

  sops.templates."keepalived-env".content = ''
    KEEPALIVED_AUTH_PASS=${config.sops.placeholder.keepalived_auth_pass}
  '';

  # SOPS secret for NUT UPS password
  sops.secrets.nut_password = {
    key = "vault_secrets/core/orangepi/password";
    restartUnits = [ "upsdrv.service" "upsd.service" "upsmon.service" ];
  };
}
