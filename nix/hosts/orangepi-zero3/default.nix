{
  system = "aarch64-linux";

  deploy = {
    tags = [ "orangepi" "sbc" "server" ];
    targetHost = "10.0.9.2";
  };

  imports = [
    ./hardware.nix
    ./config.nix
    ./../../profiles/sbc.nix
  ];

  # Note: cfg values are in config.nix (shared with sd-image.nix)
  # Additional host-specific cfg can be added here:
  # cfg = {
  #   pihole.enable = true;  # Phase 3 - module not implemented yet
  # };
}
