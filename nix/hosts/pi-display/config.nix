# Kiosk display configuration for the Pi 5 Touch Display 2 host.
#
# Used by both sd-image.nix (initial image) and default.nix (deployment), the
# same split the Orange Pi hosts use. Hardware, kernel and firmware wiring lives
# in hardware.nix; everything the panel actually shows lives here.
#
# Shared repo modules (nix/profiles/*.nix -> nix/modules) are deliberately NOT
# imported yet: every profile pulls in core/ssh.nix, which moves sshd to port
# 4185 and drops password auth. Doing that on a headless SBC in the same change
# as a structural refactor risks locking SSH out for good. Staged for the next
# apply - see the README.
{ config, lib, pkgs, ... }:

let
  displayUrl = "http://127.0.0.1:8080/";
  kioskUser = "kiosk";
  wwwDir = "/var/www/pi-display";

  # labwc execs ~/.config/labwc/autostart after it has read its configuration.
  autostart = pkgs.writeShellScript "labwc-autostart" ''
    exec ${pkgs.brave}/bin/brave \
      --kiosk ${displayUrl} \
      --no-first-run \
      --no-default-browser-check \
      --disable-session-crashed-bubble \
      --disable-pinch \
      --overscroll-history-navigation=0 \
      --ozone-platform=wayland
  '';

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

  # On-screen keyboard on demand: wvkbd is installed but never started
  # automatically, so it cannot cover the test page.
  kioskKeyboard = pkgs.writeShellScriptBin "kiosk-keyboard" ''
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
    exec ${pkgs.wvkbd}/bin/wvkbd-mobintl "$@"
  '';
in
{
  networking.hostName = "pi-display";

  boot.kernelParams = lib.mkAfter [ "consoleblank=0" ];

  zramSwap.enable = true;

  hardware.graphics.enable = true;

  # TEMPORARY, while SSH reachability is unchanged on purpose: plain sshd on
  # port 22 with root reachable. Replaced wholesale by core/ssh.nix (4185,
  # key-only, AllowUsers) in the next change.
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Desk-side debug login while the panel has no working scanout. Hash is of
  # "bench". Goes away with core/ssh.nix + sops.
  users.users.root.initialHashedPassword = "$6$benchbench$L/SWrobNRkV.iUB93gv.PJywy/QX4wzN1m2YZYeF.uBbRUYLgodycFkml5WWSUxFf4eG/3lJwiGVvvDLD8/76.";

  users.users.${kioskUser} = {
    isNormalUser = true;
    home = "/home/${kioskUser}";
    createHome = true;
    extraGroups = [ "video" "render" "input" ];
  };

  # greetd exits 1 with "default_session contains no command" and gets
  # restarted every 5s if only initial_session is set, so both tables carry the
  # same labwc command. initial_session is the autologin path.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.labwc}/bin/labwc";
        user = kioskUser;
      };
      initial_session = {
        command = "${pkgs.labwc}/bin/labwc";
        user = kioskUser;
      };
    };
  };

  # Restart the session whenever it dies: greetd re-runs initial_session.
  systemd.services.greetd.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  system.activationScripts.piDisplayKioskAutostart = ''
    install -d -m 0755 -o ${kioskUser} -g users /home/${kioskUser}/.config/labwc
    install -m 0755 -o ${kioskUser} -g users ${autostart} /home/${kioskUser}/.config/labwc/autostart
  '';

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

  # Managed policy: Brave reads every JSON file under this directory.
  environment.etc."brave/policies/managed/kiosk.json".source = ./policies.json;

  environment.variables = {
    # labwc (wlroots) has no hide-cursor option; a 1px cursor theme is the
    # compositor-level workaround. With no pointer hardware attached the cursor
    # is not drawn at all.
    XCURSOR_SIZE = "1";
    NIXOS_OZONE_WL = "1";
  };

  environment.systemPackages = with pkgs; [
    brave
    evtest
    iproute2
    kioskKeyboard
    labwc
    libinput
    libraspberrypi
    python3
    wvkbd
  ];

  time.timeZone = "UTC";

  networking.firewall.allowedTCPPorts = [ 8080 ];

  system.stateVersion = "25.11";
}
