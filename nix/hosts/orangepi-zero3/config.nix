# Shared configuration for orangepi-zero3
# Used by both sd-image.nix (initial image) and default.nix (deployment)
{
  cfg = {
    orangepi-zero3.enable = true;
    pihole.enable = true;
    networking = {
      backend = "networkd";
      static = {
        interface = "end0";
        address = "10.0.9.2";
        gateway = "10.0.9.1";
        nameservers = [ "10.0.9.1" "9.9.9.9" ];
      };
    };
  };
}
