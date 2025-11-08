{ shared, ... }:
{
  # Nixos user config
  users.users.${shared.username} = {
    isNormalUser = true;
    description = "${shared.username}";
    extraGroups = [ "networkmanager" "wheel" ];
  };
  nix.settings = {
    allowed-users = [ "${shared.username}" ];
    trusted-users = [ "${shared.username}" ];
  };
}
