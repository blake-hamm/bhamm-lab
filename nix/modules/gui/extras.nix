{ inputs
, shared
, pkgs
, config
, lib
, ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.brave.nixosModules.default
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
        brave # from inputs.brave overlay (dropped from nixpkgs 26.05)
        signal-desktop
        telegram-desktop
        karere # wasistlos replacement (removed in 26.05)
        vlc
        uv
        krita
        libreoffice
        hunspell
        hunspellDicts.en_US
        (shotcut.overrideAttrs (oldAttrs: {
          qtWrapperArgs =
            (oldAttrs.qtWrapperArgs or [ ])
            ++ [
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
