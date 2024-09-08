{ lib, ... }:
{
  networking = {
    networkmanager.enable = lib.mkForce false;
    useNetworkd = true;
    firewall.enable = true;
    useDHCP = lib.mkForce false;
    enableIPv6 = lib.mkForce false;
  };
  systemd.network = {
    enable = true;
    netdevs = {
      # Bond network
      "10-bond0" = {
        netdevConfig = {
          Kind = "bond";
          Name = "enp0s4"; #bond0 preferred (required for kube-vip)
        };
        bondConfig = {
          Mode = "802.3ad";
          TransmitHashPolicy = "layer3+4";
          AdSelect = "bandwidth";
          LACPTransmitRate = "fast";
          MIIMonitorSec = "1s";
          MinLinks = 1;
        };
      };
    };
    networks = {
      # Usb Ethernet 2.5g nic as primary
      "10-enp0s20f0u2" = {
        matchConfig.Name = "enp0s20f0u2";
        networkConfig.Bond = "enp0s4";
      };
      # Built-in Ethernet nic
      "10-enp0s20f0u1" = {
        matchConfig.Name = "enp0s20f0u1";
        networkConfig.Bond = "enp0s4";
      };
      # Bond network
      "10-bond0" = {
        matchConfig.Name = "enp0s4";
        address = [ "192.168.69.14/24" ];
        gateway = [ "192.168.69.1" ];
        dns = [ "192.168.69.1" ];
        linkConfig.RequiredForOnline = "yes";
        networkConfig.DHCP = "no";
      };
    };
  };
}
