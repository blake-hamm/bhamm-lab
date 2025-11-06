{
  imports = [
    ../modules
  ];

  cfg = {
    networking.backend = "networkd";
  };
}
