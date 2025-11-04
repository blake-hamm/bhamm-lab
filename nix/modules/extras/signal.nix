{ config, lib, pkgs, username, ... }:

{
  config = lib.mkIf config.cfg.signal.enable {
    services.signald = {
      enable = true;
      user = "${username}";
    };

    environment.systemPackages = [ pkgs.signaldctl ];
  };
}
