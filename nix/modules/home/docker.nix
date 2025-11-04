{ config, lib, username, ... }:

{
  config = lib.mkIf config.cfg.docker.enable {
    virtualisation.docker.enable = true;
    users.users.${username}.extraGroups = [ "docker" ];

    virtualisation.docker.rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
