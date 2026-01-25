{
  description = "Nix config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix/release-25.05";

    sops-nix.url = "github:Mic92/sops-nix";

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, ... } @ inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      shared = import ./nix/lib;
      gen = shared.generators { lib = nixpkgs.lib; inherit shared self inputs; };
      allNixosConfigurations = gen.generateNixosConfigurations // {
        minimal-iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (import ./nix/hosts/iso)
            { nixpkgs.config.allowBroken = true; }
          ];
          specialArgs = {
            host = "minimal-iso";
            inherit self inputs shared;
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = "x86_64-linux";
              config.allowUnfree = true;
            };
          };
        };
      };
    in
    {
      nixosConfigurations = allNixosConfigurations;
      legacyPackages = forAllSystems (system: {
        nixosConfigurations = nixpkgs.lib.filterAttrs (n: v: v.pkgs.system == system) allNixosConfigurations;
      });

      nixpkgs.config.allowBroken = true;
      devShells.x86_64-linux.default = import ./nix/shell.nix {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        inherit inputs;
      };
      colmena =
        {
          meta = {
            nixpkgs = import nixpkgs {
              system = "x86_64-linux";
              config.allowUnfree = true;
            };
            specialArgs = {
              inherit self inputs shared;
              pkgs-unstable = import inputs.nixpkgs-unstable {
                system = "x86_64-linux";
                config.allowUnfree = true;
              };
            };
            nodeSpecialArgs = gen.generateNodeSpecialArgs;
          };
        } // gen.generateColmena;
    };
}
