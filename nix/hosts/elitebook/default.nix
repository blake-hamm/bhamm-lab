{
  imports = [
    ./hardware-configuration.nix
    ./../../modules/profiles/k3s-laptop-node.nix
    ./disko.nix
    ./network.nix
  ];
}
