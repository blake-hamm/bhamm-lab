{ inputs, shared, pkgs, config, lib, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  config = lib.mkIf config.cfg.gnome.enable {
    nixpkgs.config.permittedInsecurePackages = [
      "electron-19.1.9" # Required for etcher
    ];
    home-manager.users.${shared.username} = {
      home.packages = with pkgs; [
        drawio
        dbeaver-bin
        virt-manager
        obs-studio
        brave
        signal-desktop
        vlc
        uv
        krita
        (shotcut.overrideAttrs (oldAttrs: {
          qtWrapperArgs = (oldAttrs.qtWrapperArgs or [ ]) ++ [
            "--prefix XDG_DATA_DIRS : ${gtk3}/share/gsettings-schemas/${gtk3.name}"
          ];
        }))
        # gnome-network-displays
        # steam
        # etcher
        # kubectl
        # kubernetes-helm
        # argocd
      ];
    };
  };
}
