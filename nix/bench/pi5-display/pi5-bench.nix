# Pi 5 bench: nixos-raspberrypi.
#
# Kernel/display stack: nixos-raspberrypi's own pinned nixpkgs + vendor kernel
# (linux_rpi5 from its overlay) + the RP1 display module, booted firmware-direct
# by boot.loader.raspberry-pi.bootloader = "kernel" (no U-Boot, no extlinux).
#
# Question this answers: does the panel come up when the bootloader hands the
# firmware-patched device tree straight to Linux? Answer from the live bench:
# no. display_auto_detect=1 is set, but the firmware does not apply the panel
# overlay on this setup (no DSI connector, no ili9881 module, no Goodix touch),
# so the overlay is enabled explicitly below.
{ lib, nixos-raspberrypi, ... }:

{
  # Board support, the DSI/RP1 display module and the kiosk layer are imported
  # here so the root flake only has to add the sd-image module and this file.
  # `nixos-raspberrypi` arrives in specialArgs from
  # inputs.nixos-raspberrypi.lib.nixosSystem in the root flake.
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.display-rp1
    ./kiosk.nix
  ];

  # Firmware-direct boot of the generation kernel. The sd-image module already
  # selects this for variant 5; restated because the bench depends on it.
  boot.loader.raspberry-pi.bootloader = lib.mkForce "kernel";

  networking.hostName = "pi5-bench";

  # nixos-raspberrypi renders config.txt from hardware.raspberry-pi.config,
  # which has a different shape from nixos-hardware's configtxt.settings:
  # <filter>.options.<key>.{enable,value} and <filter>.dt-overlays.<name>.
  #
  # display_auto_detect=1 and dtoverlay=vc4-kms-v3d are defaults from
  # nixos-raspberrypi's modules/configtxt.nix and are left untouched.
  #
  # Firmware autodetect does NOT enable this panel here: the generated
  # config.txt carries display_auto_detect=1 and no ili9881 overlay, and the
  # live system shows no DSI connector and no ili9881/goodix modules. The
  # overlay is therefore required, not optional.
  #
  # vc4-kms-dsi-ili9881-7inch defaults to DSI1 and i2c_csi_dsi, which is the
  # CAM/DISP 1 connector the ribbon is on. Add `dsi0 = { enable = true; };` to
  # params only if the ribbon moves to CAM/DISP 0 (DSI0/i2c_csi_dsi0).
  hardware.raspberry-pi.config.all.dt-overlays.vc4-kms-dsi-ili9881-7inch = {
    enable = true;
    params = {
      sizex = {
        enable = true;
        value = 720;
      };
      sizey = {
        enable = true;
        value = 1280;
      };
      rotation = {
        enable = true;
        value = 0;
      };
    };
  };
}
