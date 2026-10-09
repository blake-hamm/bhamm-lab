{
  username = "bhamm";
  system = "x86_64-linux";
  sshPort = 4185;
  nixVersion = "25.11";

  # bhamm framework public key (private key never Nix-managed)
  sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt";

  # Generator functions
  generators = import ./generators.nix;
}
