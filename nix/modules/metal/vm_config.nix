{ inputs, host, username, host_ssh_port, ... }:
{
  imports = [
    inputs.microvm.nixosModules.microvm
    ./../profiles/minimal.nix
  ];

  # Config
  users.users.${username}.password = "";

  # Microvm
  microvm = {
    vcpu = 4;
    mem = 6144; # 6gb
    volumes = [{
      mountPoint = "/var";
      image = "var.img";
      size = 10240; # 10 gb
    }];

    shares = [{
      proto = "virtiofs";
      # proto = "9p";
      tag = "ro-store";
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
    }];

    interfaces = [
      {
        type = "user";
        id = "qemu";
        mac = "02:00:00:00:00:01";
      }
    ];

    forwardPorts = [
      { from = "host"; host.port = host_ssh_port; guest.port = 4185; }
    ];

    hypervisor = "qemu";
    socket = "control.socket";
  };
}
