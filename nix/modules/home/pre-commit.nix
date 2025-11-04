{ config, lib, inputs, username, pkgs, ... }:

{
  config = lib.mkIf config.cfg.precommit.enable {
    home-manager.users.${username} = {
      home.packages = with pkgs; [
        pre-commit
        rustup
        gcc
      ];
    };
  };
}
