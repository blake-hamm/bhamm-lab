{
  imports = [
    ./base.nix
    ../modules
  ];

  cfg = {
    networking.backend = "networkd";
    monitoring.enable = true;
    tmux.enable = true;
  };
}
