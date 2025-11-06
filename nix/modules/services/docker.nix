{ config, lib, shared, ... }:

{
  config = lib.mkIf config.cfg.docker.enable {
    virtualisation.docker.enable = true;
    users.users.${shared.username}.extraGroups = [ "docker" ];

    virtualisation.docker.rootless = lib.mkIf config.cfg.docker.rootless.enable {
      enable = true;
      setSocketVariable = true;
    };
  };
}
