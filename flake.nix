{
  description = "Nix config";

  # Raspberry Pi vendor kernel (linux-rpi) is not on cache.nixos.org; upstream
  # publishes it here. Copied from nvmd/nixos-raspberrypi's own flake nixConfig.
  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    colmena = {
      url = "github:zhaofengli/colmena/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # brave was dropped from nixpkgs 26.05 (no committer maintainer); community
    # continuation of the same package by its former nixpkgs maintainer.
    brave = {
      url = "git+https://codeberg.org/buckley310/brave-browser-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    garage-upstream = {
      url = "github:deuxfleurs-org/garage/v2.5.0";
    };

    # No upstream releases; rev pinned 2026-11-05 and bumped by hand.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/d645c71a58dbae3eb17ff551a07aea13a541cb1a";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # raspberry-pi-5 bench: ships its own pinned nixpkgs and vendor kernel, so
    # no nixpkgs follows here on purpose.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { nixpkgs, self, ... } @ inputs:
    let
      shared = import ./nix/lib;
      pkgs = import inputs.nixpkgs {
        system = shared.system;
        config.allowUnfree = true;
      };
      gen = shared.generators { lib = nixpkgs.lib; inherit shared self inputs; };
      rawHive = {
        meta = {
          nixpkgs = import nixpkgs {
            system = shared.system;
          };
          nodeNixpkgs = gen.generateNodeNixpkgs;
          specialArgs = {
            inherit self inputs shared;
          };
          nodeSpecialArgs = gen.generateNodeSpecialArgs;
        };
      } // gen.generateColmena;
      hive = inputs.colmena.lib.makeHive rawHive;
    in
    {
      devShells.x86_64-linux.default = import ./nix/shell.nix { inherit pkgs inputs; };
      devShells.aarch64-linux.default = import ./nix/shell.nix {
        pkgs = import inputs.nixpkgs {
          system = "aarch64-linux";
          config.allowUnfree = true;
        };
        inherit inputs;
      };

      colmenaHive = hive;

      # VM and iso configs without colmena
      nixosConfigurations =
        {
          # ISO image
          minimal-iso = nixpkgs.lib.nixosSystem {
            system = shared.system;
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              (import ./nix/hosts/iso)
              {
                nixpkgs.config.allowBroken = true;
              }
            ];
            specialArgs = {
              host = "minimal-iso";
              inherit self inputs shared;
            };
          };

          # Generic NixOS raw image for Proxmox (direct download approach)
          proxmox-image = nixpkgs.lib.nixosSystem {
            system = shared.system;
            modules = [
              (import ./nix/hosts/proxmox-image)
              ./nix/hosts/proxmox-image/img-build.nix
            ];
            specialArgs = {
              host = "proxmox-image";
              inherit self inputs shared;
            };
          };

          orangepi-zero3-image = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              (import ./nix/hosts/orangepi-zero3/sd-image.nix)
            ];
            specialArgs = {
              host = "orangepi-zero3";
              inherit self inputs shared;
            };
          };

          orangepi-zero3-backup-image = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              (import ./nix/hosts/orangepi-zero3-backup/sd-image.nix)
            ];
            specialArgs = {
              host = "orangepi-zero3-backup";
              inherit self inputs shared;
            };
          };

          # Raspberry Pi 5 + Touch Display 2 bring-up bench. Built from the repo
          # root like the images above:
          #   nix build .#nixosConfigurations.pi5-bench-image.config.system.build.sdImage
          # Constructed with nixos-raspberrypi's own lib and nixpkgs (per that
          # flake's README), not nixpkgs.lib.nixosSystem: the board needs the
          # vendor kernel, and there is deliberately no nixpkgs follows.
          pi5-bench-image = inputs.nixos-raspberrypi.lib.nixosSystem {
            modules = [
              inputs.nixos-raspberrypi.nixosModules.sd-image
              ./nix/bench/pi5-display/pi5-bench.nix
            ];
          };
        } // (nixpkgs.lib.mapAttrs (_: node: node) hive.nodes);
    };
}
