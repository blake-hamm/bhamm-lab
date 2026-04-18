{ config, lib, pkgs, modulesPath, shared, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ../../profiles/base.nix
  ];

  # Boot: GRUB with EFI support (nodev for pure EFI, no MBR)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  # Ensure systemd-networkd is active so cloud-init network config is applied
  networking.useNetworkd = true;

  # Cloud-init for Proxmox metadata (IP, SSH keys, hostname)
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # QEMU guest agent for Proxmox integration
  services.qemuGuest.enable = true;

  # SSH on port 22 for initial provisioning (cloud-init, emergency access)
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings.PermitRootLogin = lib.mkDefault "prohibit-password";
  };

  # Inject our authorized keys into the bhamm user
  users.users.${shared.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com"
  ];

  # Allow sudo without password for wheel during initial bootstrap
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  # Filesystems: ext4 with auto-resize
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  boot.growPartition = true;
  boot.kernelParams = [ "console=ttyS0" ];
  # virtio_scsi + sd_mod required for scsi0 disk interface in Proxmox
  boot.initrd.availableKernelModules = [ "uas" "virtio_pci" "virtio_scsi" "sd_mod" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  system.stateVersion = shared.nixVersion;
}
