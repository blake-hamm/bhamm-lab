{
  imports = [
    ../modules
  ];

  # Default settings for a desktop machine
  cfg = {
    gnome.enable = true;
    podman.enable = false;
    ghostty.enable = true;
    k9s.enable = true;
    vscode.enable = true;
    precommit.enable = true;
    networking.backend = "networkmanager";
    vesktop.enable = true;
    opencode.enable = true;
    pi.enable = true;
    neovim.enable = true;
    audio.enable = true;
    tmux.enable = true;
    zsh.enable = true;
    zsh.starship.enable = true;
  };
}
