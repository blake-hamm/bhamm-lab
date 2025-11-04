{ config, lib, inputs, shared, pkgs, ... }:

{
  config = lib.mkIf config.cfg.precommit.enable {
    home-manager.users.${shared.username} = {
      home.packages = with pkgs; [
        pre-commit
        rustup
        gcc
      ];
    };
  };
}
