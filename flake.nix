{
  description = "Nix config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    colmena = {
      url = "github:zhaofengli/colmena/349b035a5027f23d88eeb3bc41085d7ee29f18ed";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix/release-25.11";

    sops-nix.url = "github:Mic92/sops-nix";

    opencode.url = "github:anomalyco/opencode/704fca074d9b14b0d34c8933f175234729ee9b6e";

    llm-agents.url = "github:numtide/llm-agents.nix";

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    garage-upstream = {
      url = "github:deuxfleurs-org/garage/v2.3.0";
    };

  };

  outputs = { nixpkgs, self, ... } @ inputs:
    let
      shared = import ./nix/lib;
      pkgs = import inputs.nixpkgs {
        system = shared.system;
        config.allowUnfree = true;
      };
      pkgs-unstable = import inputs.nixpkgs-unstable {
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
            inherit pkgs-unstable;
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
              inherit pkgs-unstable;
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
              inherit pkgs-unstable;
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
