{ lib, pkgs, ... }:
let
  # Use Orange Pi Zero 3 u-boot as base
  bootloaderPackage = pkgs.ubootOrangePiZero3;
in
{
  # Basic system settings
  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "aarch64-linux";

  # Hostname
  networking.hostName = "orangepi-zero3";

  # Use DHCP for initial network discovery
  networking.useDHCP = true;

  # Minimal kernel - use mainline for H618 support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Disable ZFS to avoid build issues
  boot.supportedFilesystems = lib.mkForce [
    "btrfs"
    "vfat"
    "f2fs"
    "xfs"
    "ext4"
  ];
  boot.initrd.supportedFilesystems = lib.mkForce [
    "btrfs"
    "vfat"
    "f2fs"
    "xfs"
    "ext4"
  ];

  # SD Image configuration
  sdImage = {
    compressImage = true;
    # Write u-boot to SD card
    postBuildCommands = ''
      dd if=${bootloaderPackage}/u-boot-sunxi-with-spl.bin of=$img \
        bs=1024 seek=8 conv=notrunc
    '';
  };

  # User configuration - matches existing setup
  users.users.bhamm = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com"
    ];
  };

  # SSH access - use standard port 22 initially for easier debugging
  # Will switch to 4185 in Phase 2
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Allow passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Minimal packages for debugging
  environment.systemPackages = with pkgs; [
    vim
    htop
    git
  ];
}
