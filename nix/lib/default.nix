{
  username = "bhamm";
  sshPort = 4185;
  nixVersion = "25.05";

  # Generator functions
  generators = import ./generators.nix;
}
