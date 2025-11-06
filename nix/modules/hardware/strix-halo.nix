{ config, pkgs-unstable, lib, ... }:
{
  config = lib.mkIf config.cfg.strix-halo.enable {
    nixpkgs.overlays = [
      (final: prev: {
        mesa = pkgs-unstable.mesa;
      })
    ];

    hardware.graphics = {
      enable = true;

      extraPackages = with pkgs-unstable; [
        mesa
        rocmPackages.clr.icd
        vulkan-tools
        vulkan-loader
        vulkan-validation-layers
      ];
    };

    environment.systemPackages = with pkgs-unstable; [
      vulkan-headers
      vulkan-tools
      vulkan-loader
      vulkan-validation-layers
      rocmPackages.rocm-smi
      rocmPackages.rocminfo
      rocmPackages.clr
      lact
    ];

    environment.variables = {
      ROC_ENABLE_PRE_VEGA = "1";
    };

    users.groups.video = { };
    users.groups.render = { };
  };
}
