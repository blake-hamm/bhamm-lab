{
  imports = [
    ../modules
  ];

  # Default settings for a desktop machine
  cfg = {
    gnome.enable = true;
    docker.enable = true;
    kitty.enable = true;
    vscode.enable = true;
    uhk.enable = true;
    precommit.enable = true;
    networking.backend = "networkmanager";
    vesktop.enable = true;
  };

  # Desktop-specific services
  services.printing.enable = true;
}
