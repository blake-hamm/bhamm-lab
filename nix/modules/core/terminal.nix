{ pkgs, ... }:
{
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
