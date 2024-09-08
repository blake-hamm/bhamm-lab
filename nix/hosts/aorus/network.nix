{ lib, ... }:
{
  networking = {
    networkmanager.enable = lib.mkForce false;
    wireless.enable = true;
    wireless.userControlled.enable = true; # To connect to wifi
    useNetworkd = true;
    firewall.enable = true;
    useDHCP = lib.mkForce false;
    enableIPv6 = lib.mkForce false;
  };
  systemd.network = {
    enable = true;
    netdevs = {
      # Bridge for VM's and host
      "10-br0" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br0";
        };
      };
      # Bond ethernet and wifi
      "10-bond0" = {
        netdevConfig = {
          Kind = "bond";
          Name = "bond0";
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
      # # Built-in 2.5g Ethernet nic
      # "10-eno1" = {
      #   matchConfig.Name = "eno1";
      #   networkConfig = {
      #     Bond = "bond0";
      #     PrimarySlave = true;
      #   };
      # };
      # # WIFI nic
      # "10-wlp4s0" = {
      #   matchConfig.Name = "wlp4s0";
      #   networkConfig.Bond = "bond0";
      # };

      # 10 gb nics
      "10-enp11s0f0" = {
        matchConfig.Name = "enp11s0f0";
        networkConfig.Bond = "bond0";
      };
      "10-enp11s0f1" = {
        matchConfig.Name = "enp11s0f1";
        networkConfig.Bond = "bond0";
      };

      # Bond network
      "10-bond0" = {
        matchConfig.Name = [ "bond0" "vm-*" ];
        networkConfig.Bridge = "br0";
      };
      # Bridge network
      "10-br0" = {
        matchConfig.Name = "br0";
        bridgeConfig = { };
        address = [ "192.168.69.12/24" ];
        gateway = [ "192.168.69.1" ];
        dns = [ "192.168.69.1" ];
        linkConfig.RequiredForOnline = "yes";
        networkConfig.DHCP = "no";
      };
    };
  };
}
