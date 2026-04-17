{
  imports = [
    ./base.nix
    ../modules
  ];

  cfg = {
    networking.backend = "networkd";
  };
}
