{
  system = "x86_64-linux";

  deploy = {
    tags = [ "garage" "server" ];
    targetHost = "10.0.20.21";
  };

  imports = [
    ./hardware-configuration.nix
    ./../../profiles/server.nix
  ];

  cfg = {
    networking = {
      static = {
        interface = "eth0";
        address = "10.0.20.21";
        gateway = "10.0.20.2";
        nameservers = [ "10.0.9.2" ];
      };
    };
  };

  # Hand off network control from cloud-init to NixOS networkd
  services.cloud-init.network.enable = false;

  # The base profile enables systemd-boot by default, but this VM was
  # provisioned with GRUB (EFI, nodev). Keep GRUB to avoid bootloader conflicts.
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}
