{ inputs, lib, config, ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];

  # ZFS
  networking.hostId = "806a53e4";
  boot.kernelPackages = lib.mkForce config.boot.zfs.package.latestCompatibleLinuxPackages;
  boot.kernelParams = [ "nohibernate" ];
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.extraPools = [ "zpool_ssd" ];
  boot.extraModprobeConfig = ''
    options zfs zfs_autoimport_disable=0
  '';
  # services.prometheus.exporters.zfs.enable = config.prometheus.exporters.enable;
  # prometheus.scrapeTargets = [
  #   "127.0.0.1:${builtins.toString config.services.prometheus.exporters.zfs.port}"
  # ];

  # Devices
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B77845B74E3";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              end = "-32G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            swap = {
              size = "100%";
              content = {
                type = "swap";
              };
            };
          };
        };
      };
    };
  };
}
