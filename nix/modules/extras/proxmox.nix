{ inputs, system, ... }:
{

  imports =
    [
      inputs.proxmox-nixos.nixosModules.proxmox-ve
    ];

  services.proxmox-ve.enable = true;
  nixpkgs.overlays = [
    inputs.proxmox-nixos.overlays.${system}
  ];

}
