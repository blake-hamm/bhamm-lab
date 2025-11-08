{ inputs, shared, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${shared.username} = {
    programs.git = {
      enable = true;

      userName = "Blake Hamm";
      userEmail = "blake.j.hamm@gmail.com";

      extraConfig = {
        init.defaultBranch = "main";
        credential.helper = "store";
      };
    };
  };
}
