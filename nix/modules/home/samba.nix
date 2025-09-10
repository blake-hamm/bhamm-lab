{ username, pkgs, ... }:
{
  # Required package for CIFS mounting
  environment.systemPackages = [ pkgs.cifs-utils ];

  fileSystems = {
    # Mount the k8s Samba share
    "/mnt/storage/k8s" = {
      device = "//10.0.20.11/k8s";
      fsType = "cifs";
      options =
        let
          automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
          guest_opts = "guest,uid=1000,gid=100,iocharset=utf8,file_mode=0664,dir_mode=0775";
        in
        [ "${automount_opts},${guest_opts}" ];
    };

    # Mount the bhamm Samba share
    "/home/${username}/smb" = {
      device = "//10.0.20.11/bhamm";
      fsType = "cifs";
      options =
        let
          automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
          guest_opts = "guest,uid=1000,gid=100,iocharset=utf8,file_mode=0664,dir_mode=0775";
        in
        [ "${automount_opts},${guest_opts}" ];
    };
  };
}
