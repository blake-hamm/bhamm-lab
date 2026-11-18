# Debug-only HTTP page for the Pi 5 Touch Display 2 host. It prints this host's
# global IPv4 addresses so the address can be read off the panel or browsed
# from the desk.
{ pkgs, ... }:

let
  wwwDir = "/var/www/pi-display";

  # Rewrites the served page with this host's global IPv4 addresses, so the
  # address can be read off the panel instead of from a serial console.
  pageWriter = pkgs.writeShellScript "pi-display-page-write" ''
    set -eu
    install -d ${wwwDir}
    ips="$(${pkgs.iproute2}/bin/ip -4 -o addr show scope global \
      | ${pkgs.gawk}/bin/awk '{ print $4 }' \
      | ${pkgs.coreutils}/bin/cut -d/ -f1 \
      | ${pkgs.coreutils}/bin/tr '\n' ' ')"
    ${pkgs.gnused}/bin/sed "s|__HOST_IPS__|$ips|g" ${./index.html} \
      > ${wwwDir}/index.html
  '';
in
{
  systemd.services.pi-display-page = {
    description = "Write the pi-display kiosk page";
    wantedBy = [ "multi-user.target" ];
    before = [ "pi-display-web.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pageWriter;
    };
  };

  systemd.services.pi-display-web = {
    description = "Static HTTP server for the pi-display kiosk page";
    wantedBy = [ "multi-user.target" ];
    after = [ "pi-display-page.service" ];
    requires = [ "pi-display-page.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8080 --bind 0.0.0.0 --directory ${wwwDir}";
      Restart = "always";
      RestartSec = 2;
    };
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
