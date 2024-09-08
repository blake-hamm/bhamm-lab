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
  ];
}
