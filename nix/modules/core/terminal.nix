{ pkgs, ... }:
{
  programs.vim.enable = true;
  programs.vim.defaultEditor = true;

  environment.systemPackages = with pkgs; [
    tree
    htop
    jq
  ];
  environment.interactiveShellInit = ''
    if [ "$TERM" = "xterm-kitty" ]; then
      export TERM=xterm-256color
    fi
  '';
}
