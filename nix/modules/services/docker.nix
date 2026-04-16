{ config, lib, shared, ... }:

{
  options.cfg.docker = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Docker support";
    };
    rootless.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable rootless Docker support";
    };
  };

  config = lib.mkIf config.cfg.docker.enable {
    virtualisation.docker.enable = true;
    users.users.${shared.username}.extraGroups = [ "docker" ];

    virtualisation.docker.rootless = lib.mkIf config.cfg.docker.rootless.enable {
      enable = true;
      setSocketVariable = true;
    };
  };
}
