{ username, ... }:
{
  # Nixos user config
  users.users.${username} = {
    isNormalUser = true;
    description = "${username}";
    extraGroups = [ "networkmanager" "wheel" ];
  };
  nix.settings = {
    allowed-users = [ "${username}" ];
    trusted-users = [ "${username}" ];
  };
}
