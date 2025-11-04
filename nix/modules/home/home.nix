{ inputs, username, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  # Home manager universal config
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    extraSpecialArgs = { inherit inputs username; };
    users.${username} = {
      home.username = "${username}";
      home.homeDirectory = "/home/${username}";
      programs.home-manager.enable = true;
      systemd.user.startServices = "sd-switch";
      home.stateVersion = "23.11";
    };
  };
}
