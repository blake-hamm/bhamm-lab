{ config, lib, inputs, shared, pkgs, ... }:

{
  options.cfg.precommit.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable pre-commit hooks";
  };

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
