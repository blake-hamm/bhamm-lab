{
  username = "bhamm";
  system = "x86_64-linux";
  sshPort = 4185;
  nixVersion = "25.11";

  # Generator functions
  generators = import ./generators.nix;
}
