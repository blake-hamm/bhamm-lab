{ inputs, shared, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  # Home manager universal config
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    extraSpecialArgs = { inherit inputs shared; };
    users.${shared.username} = {
      home.username = "${shared.username}";
      home.homeDirectory = "/home/${shared.username}";
      programs.home-manager.enable = true;
      systemd.user.startServices = "sd-switch";
      home.stateVersion = "23.11";
    };
  };
}
