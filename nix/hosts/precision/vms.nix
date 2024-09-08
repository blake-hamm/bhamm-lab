{ inputs, ... }:
{
  imports = [
    inputs.microvm.nixosModules.host
  ];
  microvm.autostart = [
    "k3s-server-1"
    "k3s-server-2"
    "k3s-agent-1"
  ];
}
