{
  description = "Nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    # Disko
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Themes
    catppuccin.url = "github:catppuccin/nix";

    # MicroVM
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    # laptop-charger (in packages dir)
    # TODO: Change to monorepo
    manage_charger = {
      url = "github:blake-hamm/nix-config?dir=packages/laptop-charger";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sops nix
    sops-nix.url = "github:Mic92/sops-nix";

    # For development environment
    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { nixpkgs, self, ... } @ inputs:
    let
      username = "bhamm";
      system = "x86_64-linux";
      sshPort = 4185;
    in
    {
      # Bare metal
      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
            inherit system;
          };
          specialArgs = {
            inherit self inputs username system;
          };
          nodeSpecialArgs.framework = {
            host = "framework";
          };
          # nodeSpecialArgs.aorus = {
          #   host = "aorus";
          # };
          nodeSpecialArgs.precision = {
            host = "precision";
          };
          nodeSpecialArgs.thinkpad = {
            host = "thinkpad";
          };
          nodeSpecialArgs.elitebook = {
            host = "elitebook";
          };
        };

        framework = { name, nodes, pkgs, ... }: {
          deployment = {
            allowLocalDeployment = true;
            tags = [ "framework" "local" "desktop" ];
            targetUser = "${username}";
            targetHost = "localhost";
            targetPort = sshPort;
          };
          imports = [ ./nix/hosts/framework ];
        };

        # aorus = { name, nodes, pkgs, ... }: {
        #   deployment = {
        #     tags = [ "aorus" "server" ];
        #     targetUser = "${username}";
        #     targetHost = "192.168.69.12";
        #     targetPort = sshPort;
        #   };
        #   imports = [ ./nix/hosts/aorus ];
        # };

        precision = { name, nodes, pkgs, ... }: {
          deployment = {
            tags = [ "precision" "server" ];
            targetUser = "${username}";
            targetHost = "192.168.69.13";
            targetPort = sshPort;
          };
          imports = [ ./nix/hosts/precision ];
        };

        thinkpad = { name, nodes, pkgs, ... }: {
          deployment = {
            tags = [ "thinkpad" "server" "k3s" ];
            targetUser = "${username}";
            targetHost = "192.168.69.14";
            targetPort = sshPort;
          };
          imports = [ ./nix/hosts/thinkpad ];
        };

        elitebook = { name, nodes, pkgs, ... }: {
          deployment = {
            tags = [ "elitebook" "server" ];
            targetUser = "${username}";
            targetHost = "192.168.69.15";
            targetPort = sshPort;
          };
          imports = [ ./nix/hosts/elitebook ];
        };
      };

      # VM and iso configs without colmena
      nixosConfigurations = {
        # ISO image
        minimal-iso = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (import ./nix/hosts/iso)
            {
              nixpkgs.config.allowBroken = true;
            }
          ];
          specialArgs = {
            host = "minimal-iso";
            inherit self inputs username;
          };
        };

        # example = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [
        #     (import ./nix/hosts/example)
        #   ];
        #   specialArgs = {
        #     host = "example";
        #     inherit self inputs username system;
        #   };
        # };

      };

      devShells."${system}".default =
        let
          pkgs = import nixpkgs {
            inherit system;
            config = { allowUnfree = true; };
            overlays = [ ];
          };
          inherit (inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; }) mkPoetryEnv defaultPoetryOverrides;
          pythonPoetryEnv =
            let
              pypkgs-build-requirements = {
                mkdocs-material = [ "hatchling" ];
              };
              p2n-overrides = defaultPoetryOverrides.extend (final: prev:
                builtins.mapAttrs
                  (package: build-requirements:
                    (builtins.getAttr package prev).overridePythonAttrs (old: {
                      buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg prev else pkg) build-requirements);
                    })
                  )
                  pypkgs-build-requirements
              );
            in
            mkPoetryEnv {
              projectDir = ./python/.;
              overrides = p2n-overrides;
            };
        in
        pkgs.mkShell {
          # packages = [ pythonPoetryEnv ];
          packages = [
            (pkgs.python3.withPackages (python-pkgs: [
              python-pkgs."mkdocs-material"
              python-pkgs."hvac"
              python-pkgs."httpx"
            ]))
          ];

          nativeBuildInputs = with pkgs; [
            vault
            kubectl
            kubernetes-helm
            argocd
            k9s
            colmena
            poetry
            sops
            mkdocs
            ansible
            ansible-lint
            sshpass
            opentofu
            terraform
            tflint
            trivy
            terrascan
          ];

          shellHook = ''
            # Install ansible galaxy requirements
            ansible-galaxy install -r ansible/requirements.yml

            # Source .env file
            if [ -f .env ]; then
              export $(grep -v '^#' .env | xargs)
            fi

            # Define python intepreter for ansible
            export NIX_PYTHON_INTERPRETER=$(which python)

            # Prefect server vars
            export PREFECT_API_URL=https://prefect.bhamm-lab.com/api
            export PREFECT_UI_API_URL=https://prefect.bhamm-lab.com/api
            export PREFECT_API_TLS_INSECURE_SKIP_VERIFY=true
          '';
        };
    };
}
