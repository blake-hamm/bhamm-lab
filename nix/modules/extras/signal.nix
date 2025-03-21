{ pkgs, username, ... }:
{

  services.signald = {
    enable = true;
    user = "${username}";
  };

  environment.systemPackages = [ pkgs.signaldctl ];
}
