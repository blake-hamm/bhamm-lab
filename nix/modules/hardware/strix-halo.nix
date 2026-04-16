{ config, pkgs-unstable, lib, ... }:
{
  options.cfg.strix-halo.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable Strix Halo specific settings";
  };

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


    services.tuned = {
      enable = true;
      profiles = {
        strix-halo = {
          main = {
            include = "accelerator-performance";
          };
        };
      };
    };

    systemd.services.tuned-set-profile = {
      description = "Set TuneD profile";
      after = [ "tuned.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs-unstable.tuned}/bin/tuned-adm profile accelerator-performance";
      };
    };

    users.groups.video = { };
    users.groups.render = { };
  };
}
