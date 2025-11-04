{
  description = "Nix config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    sops-nix.url = "github:Mic92/sops-nix";

  };

  outputs = { nixpkgs, self, ... } @ inputs:
    let
      shared = import ./nix/lib;
      pkgs = import inputs.nixpkgs {
        system = shared.system;
        config.allowUnfree = true;
      };
    in
    {
      devShells.x86_64-linux.default = import ./nix/shell.nix { inherit pkgs; };
      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
            system = shared.system;
          };
          specialArgs = {
            inherit self inputs shared;
          };
          nodeSpecialArgs.framework = {
            host = "framework";
          };
        };

        framework = { name, nodes, pkgs, ... }: {
          deployment = {
            allowLocalDeployment = true;
            tags = [ "framework" "local" "desktop" ];
            targetUser = shared.username;
            targetHost = "localhost";
            targetPort = shared.sshPort;
          };
          imports = [ ./nix/hosts/framework ];
        };
      };

      # VM and iso configs without colmena
      nixosConfigurations = {
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
      };
    };
}
