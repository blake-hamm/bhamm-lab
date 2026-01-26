{
  username = "bhamm";
  system = "x86_64-linux";
  getSystemForHost = host: if host.cfg ? "aarch64" && host.cfg.aarch64.enable then "aarch64-linux" else "x86_64-linux";
  sshPort = 4185;
  nixVersion = "25.11";

  # Generator functions
  generators = import ./generators.nix;
}
