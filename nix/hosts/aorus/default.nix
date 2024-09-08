{
  imports = [
    ./hardware-configuration.nix
    ./../../modules/profiles/minimal.nix
    ./disko.nix
    ./nfs.nix
    ./network.nix
  ];
}
