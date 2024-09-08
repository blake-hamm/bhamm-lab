{ inputs, username, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${username} = {
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
