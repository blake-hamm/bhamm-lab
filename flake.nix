{
  description = "Nix config";

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
        } // (nixpkgs.lib.mapAttrs (_: node: node) hive.nodes);
    };
}
