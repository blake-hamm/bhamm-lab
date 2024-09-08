{ pkgs, username, lib, ... }:
{
  users.users.${username} = {
    openssh.authorizedKeys.keys = [
      # bhamm framework
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKsS2H4frdi7AvzkGMPMRaQ+B46Af5oaRFtNJY3uCHt blake.j.hamm@gmail.com"
    ];
  };
  services.openssh = {
    enable = true;
    ports = [ 4185 ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = lib.mkDefault "no";
      UseDns = true;
      X11Forwarding = false;
      AllowUsers = [ "${username}" ];
    };
  };
  services.fail2ban = {
    enable = true;
    extraPackages = [ pkgs.curl ];

    jails.sshd = lib.mkForce ''
      enabled = true
      port    = 4185
      filter  = sshd
      backend = systemd
    '';
  };
  programs.ssh = {
    extraConfig = ''
      Host 192.168.69.*
        Port 4185
    '';
  };
}
