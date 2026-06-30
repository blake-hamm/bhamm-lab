{ config, lib, shared, ... }:

{
  options.cfg.podman = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Podman support";
    };
    rootless.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable rootless Podman support";
    };
  };

  config = lib.mkIf config.cfg.podman.enable {
    virtualisation.containers.enable = true;
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    users.users.${shared.username}.extraGroups = [ "podman" ];
  };
}
