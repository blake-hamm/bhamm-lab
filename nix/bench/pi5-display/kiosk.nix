# Kiosk layer for the Pi 5 display bench. Everything the panel sees lives here;
# the kernel and display stack are configured in pi5-bench.nix.
#
{ config, lib, pkgs, ... }:

let
  benchUrl = "http://127.0.0.1:8080/";
  kioskUser = "kiosk";
  wwwDir = "/var/www/bench";

  # labwc execs ~/.config/labwc/autostart after it has read its configuration.
  autostart = pkgs.writeShellScript "labwc-autostart" ''
    exec ${pkgs.brave}/bin/brave \
      --kiosk ${benchUrl} \
      --no-first-run \
      --no-default-browser-check \
      --disable-session-crashed-bubble \
      --disable-pinch \
      --overscroll-history-navigation=0 \
      --ozone-platform=wayland
  '';

  # Rewrites the served page with this host's global IPv4 addresses, so the
  # address can be read off the panel instead of from a serial console.
  pageWriter = pkgs.writeShellScript "bench-page-write" ''
    set -eu
    install -d ${wwwDir}
    ips="$(${pkgs.iproute2}/bin/ip -4 -o addr show scope global \
      | ${pkgs.gawk}/bin/awk '{ print $4 }' \
      | ${pkgs.coreutils}/bin/cut -d/ -f1 \
      | ${pkgs.coreutils}/bin/tr '\n' ' ')"
    ${pkgs.gnused}/bin/sed "s|__HOST_IPS__|$ips|g" ${./testpage/index.html} \
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
  boot.kernelParams = lib.mkAfter [ "consoleblank=0" ];

  zramSwap.enable = true;

  hardware.graphics.enable = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Throwaway bench on a desk, reachable only from the LAN: root gets a known
  # password so the panel can be debugged over SSH (hash is of "bench").
  users.users.root.initialHashedPassword = "$6$benchbench$L/SWrobNRkV.iUB93gv.PJywy/QX4wzN1m2YZYeF.uBbRUYLgodycFkml5WWSUxFf4eG/3lJwiGVvvDLD8/76.";

  users.users.${kioskUser} = {
    isNormalUser = true;
    home = "/home/${kioskUser}";
    createHome = true;
    extraGroups = [ "video" "render" "input" ];
  };

  services.greetd = {
    enable = true;
    settings.initial_session = {
      command = "${pkgs.labwc}/bin/labwc";
      user = kioskUser;
    };
  };

  # Restart the session whenever it dies: greetd re-runs initial_session.
  systemd.services.greetd.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  system.activationScripts.benchKioskAutostart = ''
    install -d -m 0755 -o ${kioskUser} -g users /home/${kioskUser}/.config/labwc
    install -m 0755 -o ${kioskUser} -g users ${autostart} /home/${kioskUser}/.config/labwc/autostart
  '';

  systemd.services.bench-page = {
    description = "Write the Pi 5 display bench test page";
    wantedBy = [ "multi-user.target" ];
    before = [ "bench-web.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pageWriter;
    };
  };

  systemd.services.bench-web = {
    description = "Static HTTP server for the Pi 5 display bench test page";
    wantedBy = [ "multi-user.target" ];
    after = [ "bench-page.service" ];
    requires = [ "bench-page.service" ];
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
