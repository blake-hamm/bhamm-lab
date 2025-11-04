{ config, lib, pkgs, shared, ... }:

{
  config = lib.mkIf config.cfg.signal.enable {
    services.signald = {
      enable = true;
      user = "${shared.username}";
    };

    environment.systemPackages = [ pkgs.signaldctl ];
  };
}
