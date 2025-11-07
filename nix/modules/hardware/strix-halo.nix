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
    ];

    environment.variables = {
      ROC_ENABLE_PRE_VEGA = "1";
    };

    boot = {
      kernelParams = [
        "amd_iommu=off"
        "amdgpu.gttsize=122800"
        "amdgpu.vm_fragment_size=8"
        "ttm.pages_limit=31457280" # 120 gb
        "ttm.page_pool_size=25165824" # 96 gb
      ];
    };

    users.groups.video = { };
    users.groups.render = { };
  };
}
