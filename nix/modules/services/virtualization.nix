{ config, lib, shared, ... }:

{
  options.cfg.virtualization.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable virtualization tools";
  };

  config = lib.mkIf config.cfg.virtualization.enable {
    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
    users.users.${shared.username}.extraGroups = [ "libvirtd" ];
  };
}
