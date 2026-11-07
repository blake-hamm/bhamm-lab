{ config, lib, ... }:

{
  options.cfg.pihole.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Pi-hole DNS server";
  };

  config = lib.mkIf config.cfg.pihole.enable {
    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;
      openFirewallWebserver = true;
      queryLogDeleter.enable = true;
      settings = {
        dns = {
          upstreams = [ "10.0.9.1" ];
          listeningMode = "ALL";
        };
        dhcp = {
          active = false;
        };
      };
      # Lists currently live in /var/lib/pihole/gravity.db, not here.
      #
      # This option only seeds the gravity database on first boot: the setup
      # script POSTs each list once and never removes or updates entries
      # (nixpkgs#505714). On 26.05 a re-add answers "The item is already
      # present", which the script counts as a failure, so pihole-ftl-setup
      # exits 1 and leaves the host degraded on every boot after the first.
      # Upstream fixed that in b7d1324109a2 ("pihole-ftl: make list setup
      # idempotent"), which is master-only, i.e. 26.11 and later.
      #
      # Declaring no lists disables pihole-ftl-setup entirely. Both lists below
      # are already in gravity.db and blocking. Uncomment when standing up a
      # fresh machine so the first boot populates gravity.db, then comment them
      # out again so later boots stay clean.
      # lists = [
      #   {
      #     url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
      #     description = "StevenBlack Unified";
      #     type = "block";
      #     enabled = true;
      #   }
      #   {
      #     url = "https://big.oisd.nl";
      #     description = "OISD Big";
      #     type = "block";
      #     enabled = true;
      #   }
      # ];
    };
    services.pihole-web = {
      enable = true;
      ports = [ "80r" "443s" ];
    };

    # systemd-resolved binds port 53; Pi-hole needs it
    services.resolved.enable = false;

    # The following silences a benign FTL.log warning:
    # WARNING API: Failed to read /etc/pihole/versions (key: internal_error)
    systemd.tmpfiles.rules = [
      "f /etc/pihole/versions 0644 pihole pihole - -"
    ];
  };
}
