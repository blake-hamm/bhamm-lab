{
  description = "Bench harness: Raspberry Pi 5 + Touch Display 2 (DSI) bring-up";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      nixos-raspberrypi
    }:
    let
      kiosk = ./kiosk.nix;

      # Path A: nixos-hardware raspberry-pi/5 (vendor linux-rpi kernel),
      # booted the nixpkgs sd-image way (firmware -> U-Boot -> extlinux).
      bench-a = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit nixos-hardware; };
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ./bench-a.nix
          kiosk
        ];
      };

      # Path B: nixos-raspberrypi (own pinned nixpkgs, vendor kernel, RP1
      # display module, firmware-direct "kernel" bootloader).
      bench-b = nixos-raspberrypi.lib.nixosSystem {
        modules = [
          nixos-raspberrypi.nixosModules.raspberry-pi-5.base
          nixos-raspberrypi.nixosModules.raspberry-pi-5.display-rp1
          nixos-raspberrypi.nixosModules.sd-image
          ./bench-b.nix
          kiosk
        ];
      };
    in
    {
      nixosConfigurations = {
        inherit bench-a bench-b;
      };
    };
}
