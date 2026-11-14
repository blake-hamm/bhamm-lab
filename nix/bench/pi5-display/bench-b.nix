# Path B: nixos-raspberrypi.
#
# Kernel/display stack under test: nixos-raspberrypi's own pinned nixpkgs +
# vendor kernel (linux_rpi5 from its overlay) + the RP1 display module, booted
# firmware-direct by boot.loader.raspberry-pi.bootloader = "kernel" (no U-Boot,
# no extlinux).
#
# Question this path answers: does the panel come up when the bootloader hands
# the firmware-patched device tree straight to Linux, with display_auto_detect
# left at its default?
{ lib, ... }:

{
  # raspberry-pi-5.base, raspberry-pi-5.display-rp1 and sd-image are imported
  # from the flake input in flake.nix so the module paths stay greppable there.

  # Firmware-direct boot of the generation kernel. The sd-image module already
  # selects this for variant 5; restated because the bench depends on it.
  boot.loader.raspberry-pi.bootloader = lib.mkForce "kernel";

  networking.hostName = "pi5-bench-b";

  # nixos-raspberrypi renders config.txt from hardware.raspberry-pi.config,
  # which has a different shape from nixos-hardware's configtxt.settings:
  # <filter>.options.<key>.{enable,value} and <filter>.dt-overlays.<name>.
  #
  # display_auto_detect=1 and dtoverlay=vc4-kms-v3d are defaults from
  # nixos-raspberrypi's modules/configtxt.nix and are left untouched: that is
  # the behaviour under test.
  #
  # If the panel stays dark, add the overlay explicitly:
  #   hardware.raspberry-pi.config.all.dt-overlays.vc4-kms-dsi-ili9881-7inch = {
  #     enable = true;
  #     params = {
  #       sizex = { enable = true; value = 720; };
  #       sizey = { enable = true; value = 1280; };
  #       swapxy = { enable = true; value = 0; };
  #       invx = { enable = true; value = 0; };
  #       invy = { enable = true; value = 0; };
  #     };
  #   };
  #
  # On a running bench the same edit is a config.txt edit plus reboot:
  #   sudo mount /boot/firmware
  #   sudoedit /boot/firmware/config.txt
  #   sudo reboot
}
