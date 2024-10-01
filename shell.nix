# shell.nix
let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/refs/tags/24.05.tar.gz";
  pkgs = import nixpkgs { config = { allowUnfree = true; }; overlays = [ ]; };
in
pkgs.mkShell {
  buildInputs = with pkgs; [
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
  ];

  packages = [
    (pkgs.python3.withPackages (python-pkgs: [
      python-pkgs."mkdocs-material"
      python-pkgs."hvac"
    ]))
  ];

  shellHook = ''
    # Install ansible galaxy requirements
    ansible-galaxy install -r ansible/requirements.yml

    # Source .env file
    if [ -f .env ]; then
      export $(grep -v '^#' .env | xargs)
    fi
  '';
}
