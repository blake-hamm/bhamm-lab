# Raspberry Pi 5 (4 GB) + official Touch Display 2 (7", 720x1280, DSI1).
#
# Unlike the other hosts' hardware.nix this file is not nixos-generate-config
# output: the board is firmware-direct booted from SD, the filesystems are
# declared once in config.nix (shared with the colmena node) and the initrd
# module set comes from the vendor board module. What lives here is the board
# support module, the kernel/firmware overlays and the display wiring.
{ config, lib, pkgs, nixos-raspberrypi, ... }:

{
  imports = with nixos-raspberrypi.nixosModules; [
    # Vendor kernel + firmware overlays and pkgs.rpi. nixos-raspberrypi's own
    # lib.nixosSystem injects these modules; the colmena node is evaluated by
    # plain nixpkgs lib.evalModules, so it has to import them explicitly.
    nixos-raspberrypi.lib.inject-overlays
    nixpkgs-rpi
    trusted-nix-caches

    raspberry-pi-5.base
  ];

  # nixos-raspberrypi only supports aarch64-linux, and this node is evaluated
  # with that flake's own nixpkgs (see the nodeNixpkgs pin in the root flake).
  nixpkgs.hostPlatform = "aarch64-linux";

  # Firmware-direct boot of the generation kernel from SD: the bootloader *is*
  # the kernel, no U-Boot and no extlinux. sd-image-raspberrypi.nix already
  # selects this for variant 5; restated because the panel bring-up depends on
  # the firmware handing its patched device tree straight to Linux.
  boot.loader.raspberry-pi.bootloader = lib.mkForce "kernel";

  # nix/modules/core/boot.nix (imported via profiles/sbc.nix) defines these at
  # normal priority, so they win over nvmd's lib.mkDefault and must be forced
  # back to this board's values:
  #
  #   boot.kernelPackages = pkgs.<generic mainline linuxPackages>
  #     -> a generic aarch64 mainline kernel: no linux-rpi, none of the RP1 DSI
  #        patches, no vendor device trees. The build still succeeds and the
  #        board boots, so nothing reports the loss - the panel just never
  #        comes back. This one is silent.
  #
  #   boot.loader.systemd-boot.enable = mkDefault true
  #     -> a second definition of system.build.installBootLoader, which is a
  #        hard evaluation error ("Only one bootloader can be enabled at a
  #        time"). This one is loud.
  #
  # Same expression nvmd's raspberry-pi-5 module defaults to.
  boot.kernelPackages =
    lib.mkForce
      nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.linuxPackages_rpi5;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # nixos-raspberrypi renders config.txt from hardware.raspberry-pi.config,
  # which has a different shape from nixos-hardware's configtxt.settings:
  # <filter>.options.<key>.{enable,value} and <filter>.dt-overlays.<name>.
  #
  # display_auto_detect=1 and dtoverlay=vc4-kms-v3d are defaults from the
  # vendor module and are left untouched.
  #
  # Firmware autodetect does NOT enable this panel: the generated config.txt
  # carries display_auto_detect=1 and no ili9881 overlay, and the booted system
  # shows no DSI connector and no ili9881/goodix modules. The overlay below is
  # therefore mandatory, not a fallback.
  #
  # vc4-kms-dsi-ili9881-7inch defaults to DSI1 and i2c_csi_dsi, which is the
  # CAM/DISP 1 connector the ribbon is on. The `dsi0` parameter is deliberately
  # omitted: it selects DISP0/DSI0 (i2c_csi_dsi0). Add
  # `dsi0 = { enable = true; };` to params only if the ribbon moves to CAM/DISP 0.
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

  # NOTE: nixos-raspberrypi.nixosModules.raspberry-pi-5.display-rp1 is NOT
  # imported on purpose. It only writes an X11 OutputClass
  # (services.xserver.extraConfig) for the rp1-dsi/vec/dpi drivers, which is
  # inert under this host's Wayland (labwc) session.
}
