# Path A: nixos-hardware raspberry-pi/5.
#
# Kernel/display stack under test: the Raspberry Pi Foundation's downstream
# linux-rpi (pinned by nixos-hardware's raspberry-pi/common/kernel.nix), driven
# by the nixpkgs aarch64 SD image (firmware -> U-Boot -> extlinux).
#
# Question this path answers: does the panel come up with the vendor kernel and
# firmware display auto-detect alone, with no explicit dtoverlay?
{ config, lib, pkgs, nixos-hardware, ... }:

let
  cfg = config.hardware.raspberry-pi.configtxt;
  firmwareDir = "${pkgs.raspberrypifw}/share/raspberrypi/boot";
in
{
  imports = [
    "${nixos-hardware}/raspberry-pi/5"
    "${nixos-hardware}/raspberry-pi/common/config-txt.nix"
    "${nixos-hardware}/raspberry-pi/common/config-txt-defaults.nix"
  ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "pi5-bench-a";

  # nixos-hardware renders config.txt from this option and nothing else writes
  # it, so the whole file below is the bench's config.txt.
  #
  # NOTE: this nixos-hardware revision has no deviceTreeOverlays option: the
  # nixos-hardware config.txt module only exposes settings.<filter> and file.
  # dtoverlay lines are therefore expressed as a list under settings.<filter>.
  hardware.raspberry-pi.configtxt.settings = {
    all = {
      kernel = "u-boot.bin";
      arm_64bit = true;

      # display_auto_detect=1, disable_fw_kms_setup=1, dtoverlay=vc4-kms-v3d
      # and arm_boost=1 all come from nixos-hardware's config-txt-defaults.nix.
      # That default is the thing under test: on Model B and later the firmware
      # is supposed to detect the Touch Display 2 on DSI0 and apply
      # vc4-kms-dsi-ili9881-7inch by itself.
      #
      # If the panel stays dark, flip the next line (lists REPLACE rather than
      # merge, so vc4-kms-v3d has to be restated) and rebuild:
      #   dtoverlay = [ "vc4-kms-v3d" "vc4-kms-dsi-ili9881-7inch" ];
      #
      # Overlay parameters are comma-separated on the same entry. Rotation and
      # mirroring of a portrait-native 720x1280 panel:
      #   dtoverlay = [
      #     "vc4-kms-v3d"
      #     "vc4-kms-dsi-ili9881-7inch,sizex=720,sizey=1280,swapxy=0,invx=0,invy=0"
      #   ];
      #
      # The same edit can be made on the running system without a rebuild:
      #   sudo mount /boot/firmware   # it is noauto in the nixpkgs sd-image
      #   sudoedit /boot/firmware/config.txt
      #   sudo reboot
    };

    pi5 = {
      # U-Boot sometimes picks up ghost UART input on the Pi 5 and interrupts
      # the boot process; the stock nixpkgs image disables it too.
      enable_uart = false;
    };
  };

  # Replace the stock U-Boot firmware payload with the same files plus our
  # generated config.txt, and add the Pi 5 device trees U-Boot hands to Linux.
  sdImage.populateFirmwareCommands = lib.mkForce ''
    (cd ${firmwareDir} && cp bootcode.bin fixup*.dat start*.elf $NIX_BUILD_TOP/firmware/)
    cp ${pkgs.ubootRaspberryPiAarch64}/u-boot.bin firmware/u-boot.bin
    cp ${cfg.file} firmware/config.txt
    cp ${firmwareDir}/bcm2712-rpi-5-b.dtb firmware/
    cp ${firmwareDir}/bcm2712-d-rpi-5-b.dtb firmware/
  '';

  # Mount the firmware partition on a running bench so config.txt can be edited
  # from SSH; nofail keeps a broken vfat from wedging boot.
  fileSystems."/boot/firmware".options = lib.mkForce [ "rw" "nofail" ];
}
