{ inputs, shared, pkgs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager.users.${shared.username} = {
    home.packages = with pkgs; [
      gh
    ];

    # Public-key-only allowed signers file for SSH commit signature
    # verification. Private key is never Nix-managed.
    home.file.".ssh/allowed_signers".text =
      "blake.j.hamm@gmail.com ${shared.sshPublicKey}\n";

    programs.git = {
      enable = true;

      signing = {
        key = "~/.ssh/id_ed25519.pub";
        signByDefault = true;
      };

      settings = {
        user.name = "Blake Hamm";
        user.email = "blake.j.hamm@gmail.com";
        init.defaultBranch = "main";
        credential.helper = "store";
        pull.rebase = true;
        push.autoSetupRemote = true;
        gpg.format = "ssh";
        gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
        core.editor = "nvim";
      };
    };
  };
}
