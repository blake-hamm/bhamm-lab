{ inputs, username, ... }:
{

  imports =
    [
      inputs.sops-nix.nixosModules.sops
    ];

  sops.defaultSopsFile = ../../secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  # sops.age.keyFile = "/home/bhamm/.config/sops/age/keys.txt";
  sops.age.sshKeyPaths = [ "/home/${username}/.ssh/id_ed25519" "/etc/ssh/ssh_host_ed25519_key" ];

}
