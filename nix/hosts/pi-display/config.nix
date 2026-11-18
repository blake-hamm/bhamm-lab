# Kiosk display configuration for the Pi 5 Touch Display 2 host.
#
# Used by both sd-image.nix (initial image) and default.nix (deployment), the
# same split the Orange Pi hosts use. Hardware, kernel and firmware wiring lives
# in hardware.nix; the panel's kiosk session lives in kiosk.nix and its debug
# page in page.nix.
#
# This file holds the host's shared storage/network facts for sd-image.nix and
# default.nix; the kiosk session is in kiosk.nix, the debug page in page.nix.
# Hardware, kernel and panel wiring live in hardware.nix; the shared
# desktop-free module set (core, network, ssh) comes from profiles/sbc.nix.
{ config, lib, pkgs, ... }:

{
  imports = [ ../../profiles/sbc.nix ./kiosk.nix ./page.nix ];

  # sbc.nix switches cfg.networking.backend to networkd, and the network module
  # emits no DHCP client for an interface it was never told about, so the wired
  # NIC must be declared or the host comes up with no address at all.
  cfg.networking.interfaces.end0 = { mode = "dhcp"; };

  # Root and firmware filesystems. The SD image gets these from
  # nixpkgs' installer/sd-card/sd-image.nix, but the colmena node does not
  # import that module and NixOS asserts on a system with no root filesystem
  # ("The 'fileSystems' option does not specify your root file system").
  # Declaring them in this file - the one both the image and the node import -
  # keeps a single source of truth and lets `colmena apply` install a
  # generation onto the real firmware partition instead of a plain directory
  # on the root filesystem.
  #
  # Everything here is lib.mkDefault on purpose. In the image the sd-image
  # module defines device/fsType at normal priority and nvmd's
  # sd-image-raspberrypi.nix overrides the firmware options with lib.mkForce,
  # so those definitions still win unchanged there (mkDefault never conflicts
  # with a plain definition and always loses to it); the node, which has only
  # these, gets the same values.
  #
  # The labels are the sd-image option defaults at the nixpkgs revision locked
  # in flake.lock (sdImage.rootVolumeLabel = "NIXOS_SD",
  # sdImage.firmwarePartitionName = "FIRMWARE"). They cannot be written as
  # config.sdImage.* here because those options only exist when the sd-image
  # module is imported. If either sdImage option is ever overridden in
  # sd-image.nix, the matching label here must change in the same commit.
  fileSystems = {
    "/" = {
      device = lib.mkDefault "/dev/disk/by-label/NIXOS_SD";
      fsType = lib.mkDefault "ext4";
      options = lib.mkDefault [ "noatime" ];
    };

    "/boot/firmware" = {
      device = lib.mkDefault "/dev/disk/by-label/FIRMWARE";
      fsType = lib.mkDefault "vfat";
      # Same set nvmd's sd-image module forces: automount on first access so
      # switch-to-configuration can write config.txt/kernels/overlays without
      # an explicit mount, and unmount after a minute idle.
      options = lib.mkDefault [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  # Mirrors sd-image.nix so the node's initrd is built from the same module
  # set as the image's. Not a boot requirement on its own: the bcm2712 vendor
  # kernel builds the SDHCI/MMC and ext4 drivers in (=y), so stage-1 does not
  # need modules to mount the root partition.
  hardware.enableAllHardware = lib.mkDefault true;

  boot.kernelParams = lib.mkAfter [ "consoleblank=0" ];

  zramSwap.enable = true;

  hardware.graphics.enable = true;

  # Desk-side debug login while the panel has no working scanout. Hash is of
  # "bench". Goes away with core/ssh.nix + sops.
  users.users.root.initialHashedPassword = "$6$benchbench$L/SWrobNRkV.iUB93gv.PJywy/QX4wzN1m2YZYeF.uBbRUYLgodycFkml5WWSUxFf4eG/3lJwiGVvvDLD8/76.";

  environment.systemPackages = with pkgs; [
    evtest
    iproute2
    libraspberrypi
    python3
  ];
}
