{ config, lib, shared, ... }:

{
  config = lib.mkIf config.cfg.virtualization.enable {
    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
    users.users.${shared.username}.extraGroups = [ "libvirtd" ];
  };
}
