# nix/hosts/tail/disko.nix
{ inputs, ... }: {
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      # Boot Drive (500GB Kingston)
      boot = {
        device = "/dev/disk/by-id/nvme-KINGSTON_SNV3S500G_50026B76873EB3A6";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "1G";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };

      # Storage Drive (2TB Crucial)
      storage = {
        device = "/dev/disk/by-id/nvme-CT2000T500SSD8_252150742E92";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/var/mnt/local-path-provisioner";
              };
            };
          };
        };
      };
    };
  };
}
