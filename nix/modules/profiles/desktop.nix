{
  imports = [
    ../options.nix
    ../core
    ../home
    ../hardware
    ../extras
  ];

  # Default settings for a desktop machine
  cfg = {
    gnome.enable = true;
    docker.enable = true;
    kitty.enable = true;
    vscode.enable = true;
    uhk.enable = true;
    precommit.enable = true;
  };
}
