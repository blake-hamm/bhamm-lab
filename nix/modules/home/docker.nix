{ username, ... }:
{
  virtualisation.docker.enable = true;
  users.users.${username}.extraGroups = [ "docker" ];

  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
}
