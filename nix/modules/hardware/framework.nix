{ config, lib, pkgs, inputs, ... }:

{
  options.cfg.framework.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Framework specific settings";
  };

  imports = [
    inputs.nixos-hardware.nixosModules.framework-13-7040-amd
  ];

  config = lib.mkIf config.cfg.framework.enable {
    services = {
      fwupd.enable = lib.mkDefault true;
      power-profiles-daemon.enable = lib.mkDefault true;

      # nixos-hardware enables fprintd service, but the Framework 13 AMD
      # Goodix sensor (27c6:609c) requires the TOD driver for enrollment.
      fprintd.tod.enable = lib.mkDefault true;
      fprintd.tod.driver = lib.mkDefault pkgs.libfprint-2-tod1-goodix;
    };

    # Allow fingerprint for login and screen unlock.
    security.pam.services.login.fprintAuth = lib.mkDefault true;
  };
}
