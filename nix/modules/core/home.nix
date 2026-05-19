{ inputs, shared, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  # Home manager universal config
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs shared; };
    sharedModules = [
      inputs.catppuccin.homeModules.catppuccin
      inputs.nvf.homeManagerModules.default
    ];
    users.${shared.username} = {
      home.username = "${shared.username}";
      home.homeDirectory = "/home/${shared.username}";
      programs.home-manager.enable = true;
      systemd.user.startServices = "sd-switch";
      home.stateVersion = "${shared.nixVersion}";
      # Universal home-manager settings only — theming and tools are opt-in per profile
    };
  };
}
