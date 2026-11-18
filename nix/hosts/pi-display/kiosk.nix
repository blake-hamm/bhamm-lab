# On-panel kiosk session for the Pi 5 Touch Display 2 host: greetd -> labwc ->
# Brave, the kiosk user it runs as, and the browser policy that pins it.
{ pkgs, ... }:

let
  displayUrl = "http://127.0.0.1:8080/";
  kioskUser = "kiosk";

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

  # On-screen keyboard on demand: wvkbd is installed but never started
  # automatically, so it cannot cover the test page.
  kioskKeyboard = pkgs.writeShellScriptBin "kiosk-keyboard" ''
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
    exec ${pkgs.wvkbd}/bin/wvkbd-mobintl "$@"
  '';
in
{
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
    kioskKeyboard
    labwc
    libinput
    wvkbd
  ];
}
