{ config, lib, ... }:
{
  imports = [
    ./sbc.nix
  ];

  # SOPS secrets for Keepalived authentication (shared across primary/backup)
  sops.secrets.keepalived_auth_pass = {
    sopsFile = ../secrets.yaml;
    key = "keepalived_auth_pass";
  };

  sops.templates."keepalived-env".content = ''
    KEEPALIVED_AUTH_PASS=${config.sops.placeholder.keepalived_auth_pass}
  '';
}
