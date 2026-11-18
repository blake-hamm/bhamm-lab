# Network interfaces for the Pi 5 kiosk host.
#
# profiles/sbc.nix sets cfg.networking.backend to "networkd" and the network
# module emits no DHCP client for an interface it was never told about, so both
# NICs are declared here. end0 stays on DHCP permanently: it is the recovery
# path (and colmena's deploy target) and sits on a different subnet than wld0,
# so there is no same-subnet ARP flux between them.
{ config, lib, ... }:

{
  cfg.networking.interfaces = {
    end0 = { mode = "dhcp"; };

    # Static on the metal VLAN. wpa_supplicant owns L2 (association) for wld0
    # and systemd-networkd owns L3 for the same device, so declaring the
    # interface here is what gives it an address.
    wld0 = {
      mode = "static";
      address = "10.0.20.22";
      prefixLength = 24;
      gateway = "10.0.20.1";
      # OPNsense's resolver, on the same VLAN. There is no metal -> lan rule,
      # so the lan resolver has no path once end0 is unplugged.
      nameservers = [ "10.0.20.1" ];
      # Above systemd's DHCP default-route metric (1024) so the wired link stays
      # the primary path while plugged in. Use 100 to prefer WiFi instead.
      metric = 2048;
    };
  };

  # networking.wireless.interfaces is deliberately left empty: the module then
  # auto-detects the wlan device and installs a udev rule that restarts the unit
  # if brcmfmac probes late.
  networking.wireless = {
    enable = true;
    # Hardening runs the daemon as the wpa_supplicant user, but the dbus
    # policy nixpkgs installs only lets root own fi.w1.wpa_supplicant1, so
    # -u fails with AccessDenied. The dbus control interface is only needed
    # for NetworkManager or connman; neither is enabled here.
    dbusControlled = false;
    # ext_password file: NAME=PASSWORD lines, rendered from sops below. The PSK
    # never enters the nix store or the world-readable wpa_supplicant config.
    secretsFile = config.sops.templates."wpa_supplicant-secrets".path;
    networks.Polk_Metal = {
      # The AP disables SSID broadcast; without scan_ssid=1 wpa_supplicant never
      # sends the directed probe and the network is never found.
      hidden = true;
      pskRaw = "ext:polk_metal_psk";
    };
  };

  sops.secrets.wifi_psk.key = "vault_secrets/core/pi-display/wifi_psk";

  sops.templates."wpa_supplicant-secrets" = {
    content = ''
      polk_metal_psk=${config.sops.placeholder.wifi_psk}
    '';
    # wpa_supplicant.service runs as the wpa_supplicant user (hardening is on by
    # default) and bind-mounts this file read-only, so root:root 0400 would be
    # unreadable to it.
    owner = "wpa_supplicant";
    group = "wpa_supplicant";
    mode = "0400";
    restartUnits = [ "wpa_supplicant.service" ];
  };

  # cfg80211 reads this from the kernel command line; the world regulatory
  # domain otherwise lets the driver hide or under-power channels.
  boot.kernelParams = lib.mkAfter [ "cfg80211.ieee80211_regdom=US" ];

  # An unassociated wld0 is legitimate. The network module sets
  # networking.useDHCP = false, which makes networkd-wait-online require every
  # managed link, so one unassociated wld0 would hold network-online.target for
  # up to 120s.
  systemd.network.wait-online.anyInterface = true;
}
