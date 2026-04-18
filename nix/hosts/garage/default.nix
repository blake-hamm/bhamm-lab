{
  system = "x86_64-linux";

  deploy = {
    tags = [ "garage" "server" ];
    targetHost = "10.0.20.21";
  };

  imports = [
    ./hardware-configuration.nix
    ./garage.nix
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

  # Disable cloud-init after first boot (Proxmox metadata already applied)
  services.cloud-init.enable = false;
  services.cloud-init.network.enable = false;

  # Keep virtio NIC named eth0 (matches cfg.networking.static.interface)
  networking.usePredictableInterfaceNames = false;

  # QEMU guest agent for Proxmox IP reporting and shutdown integration
  services.qemuGuest.enable = true;

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

  # Enable periodic TRIM for consumer SSD longevity
  services.fstrim.enable = true;
}
