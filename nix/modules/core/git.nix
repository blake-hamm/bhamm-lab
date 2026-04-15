{ inputs, shared, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${shared.username} = {
    programs.git = {
      enable = true;

      settings = {
        user.name = "Blake Hamm";
        user.email = "blake.j.hamm@gmail.com";
        init.defaultBranch = "main";
        credential.helper = "store";
      };
    };
  };
}
