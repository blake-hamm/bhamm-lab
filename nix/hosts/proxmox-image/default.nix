{ config, lib, pkgs, modulesPath, shared, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ../../profiles/base.nix
  ];

  # The virtualisation/proxmox-image.nix module (imported via --image-variant proxmox)
  # already configures: GRUB bootloader, filesystems, cloud-init, qemu-guest-agent,
  # sshd, and growPartition. We only add our customizations here.

  # Ensure root can log in with keys for initial cloud-init provisioning.
  # The proxmox module enables sshd by default; we just ensure root key login works.
  services.openssh.settings.PermitRootLogin = lib.mkDefault "prohibit-password";

  # Inject our authorized keys into the bhamm user.
  # (The base.nix profile already creates the user.)
  users.users.${shared.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn6e5VeOkY4WcW0wPmz8uWj+yd+kulj7Ls7upTdKFUO gitea@bhamm-lab.com"
  ];

  # Allow sudo without password for wheel during initial bootstrap
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  system.stateVersion = shared.nixVersion;
}
