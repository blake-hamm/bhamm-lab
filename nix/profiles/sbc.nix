{ lib, ... }:
{
  imports = [
    ../modules
  ];

  # SBC-specific defaults
  cfg = {
    networking.backend = "networkd";
    # Disable desktop features
    gnome.enable = lib.mkDefault false;
    docker.enable = lib.mkDefault false;
    kitty.enable = lib.mkDefault false;
    vscode.enable = lib.mkDefault false;
    uhk.enable = lib.mkDefault false;
    vesktop.enable = lib.mkDefault false;
  };
}
