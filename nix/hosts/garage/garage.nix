# nix/hosts/garage/garage.nix
{ config, pkgs, lib, ... }:

{
  # Garage S3 Object Storage
  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    environmentFile = config.sops.templates."garage-env".path;
    extraEnvironment = {
      GARAGE_DEFAULT_BUCKET = "ceph-rgw";
    };

    settings = {
      replication_factor = 1;
      data_dir = [
        { path = "/mnt/garage/disk1"; capacity = "2T"; }
        { path = "/mnt/garage/disk2"; capacity = "2T"; }
        { path = "/mnt/garage/disk3"; capacity = "1T"; }
      ];
      rpc_bind_addr = "127.0.0.1:3901";
      s3_api = {
        api_bind_addr = "[::]:3900";
        s3_region = "garage";
      };
      admin = {
        api_bind_addr = "0.0.0.0:3903";
      };
    };
  };

  # Sops secrets for garage
  # Mode must be 0600: garage enforces owner-only permissions on secret files.
  sops.secrets.garage_rpc_secret = {
    key = "vault_secrets/core/garage/rpc_secret";
    owner = config.users.users.garage.name;
    mode = "0600";
  };

  sops.secrets.garage_admin_token = {
    key = "vault_secrets/core/garage/admin_token";
    owner = config.users.users.garage.name;
    mode = "0600";
  };

  sops.secrets.garage_s3_access_key = {
    key = "vault_secrets/core/garage/s3_access_key";
    owner = config.users.users.garage.name;
    mode = "0600";
  };

  sops.secrets.garage_s3_secret_key = {
    key = "vault_secrets/core/garage/s3_secret_key";
    owner = config.users.users.garage.name;
    mode = "0600";
  };

  # Environment file template for garage service
  # Garage supports GARAGE_*_FILE env vars since v0.8.5/v0.9.1
  sops.templates."garage-env" = {
    content = ''
      GARAGE_RPC_SECRET_FILE=${config.sops.secrets.garage_rpc_secret.path}
      GARAGE_ADMIN_TOKEN_FILE=${config.sops.secrets.garage_admin_token.path}
    '';
    owner = config.users.users.garage.name;
    mode = "0600";
  };

  # Data disk mounts: noauto + automount so boot never hangs on missing disks.
  # Disks are partitioned and formatted once manually via SSH (see migration docs).
  # The automount units trigger on first access, so garage starts cleanly once
  # the directories exist and the filesystems are ready.
  fileSystems."/mnt/garage/disk1" = {
    device = "/dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009C8-part1";
    fsType = "xfs";
    options = [ "noauto" "x-systemd.automount" "x-systemd.idle-timeout=300" ];
  };
  fileSystems."/mnt/garage/disk2" = {
    device = "/dev/disk/by-id/ata-PNY_CS900_2TB_SSD_PNY225122122301009CB-part1";
    fsType = "xfs";
    options = [ "noauto" "x-systemd.automount" "x-systemd.idle-timeout=300" ];
  };
  fileSystems."/mnt/garage/disk3" = {
    device = "/dev/disk/by-id/ata-CT1000BX500SSD1_2308E6B0E700-part1";
    fsType = "xfs";
    options = [ "noauto" "x-systemd.automount" "x-systemd.idle-timeout=300" ];
  };

  # Ensure garage starts after the automount units are available.
  # The automounts trigger on first access to /mnt/garage/disk*.
  systemd.services.garage = {
    after = [
      "mnt-garage-disk1.automount"
      "mnt-garage-disk2.automount"
      "mnt-garage-disk3.automount"
    ];
    wants = [
      "mnt-garage-disk1.automount"
      "mnt-garage-disk2.automount"
      "mnt-garage-disk3.automount"
    ];
    serviceConfig = {
      # Disable DynamicUser so we can manage permissions properly
      DynamicUser = lib.mkForce false;
      User = "garage";
      Group = "garage";
      # Keep ReadWritePaths for the data directories
      ReadWritePaths = [
        "/mnt/garage/disk1"
        "/mnt/garage/disk2"
        "/mnt/garage/disk3"
      ];
      # Conditionally bootstrap on first start (--single-node --default-bucket),
      # otherwise run normally. Secrets are read from sops-nix and exported as
      # env vars so Garage auto-creates the bucket and key with our declared
      # credentials on fresh installs.
      ExecStart = lib.mkForce (pkgs.writeShellScript "garage-start" ''
        export GARAGE_DEFAULT_ACCESS_KEY=$(cat "${config.sops.secrets.garage_s3_access_key.path}")
        export GARAGE_DEFAULT_SECRET_KEY=$(cat "${config.sops.secrets.garage_s3_secret_key.path}")

        if [ ! -d /var/lib/garage/meta ]; then
          exec ${pkgs.garage_2}/bin/garage server --single-node --default-bucket
        else
          exec ${pkgs.garage_2}/bin/garage server
        fi
      '');
    };
  };

  # Create a dedicated garage user/group for file ownership
  users.users.garage = {
    isSystemUser = true;
    group = "garage";
    description = "Garage object storage user";
    home = "/var/lib/garage";
    createHome = true;
  };
  users.groups.garage = { };

  # VLAN 30 interface for direct L2 connectivity to k8s
  # Avoids MTU black hole on L3 switch inter-VLAN routing
  networking.vlans."eth0.30" = {
    id = 30;
    interface = "eth0";
  };

  networking.interfaces."eth0.30" = {
    ipv4.addresses = [{ address = "10.0.30.21"; prefixLength = 24; }];
  };

  # Open firewall for S3 API and admin/metrics
  networking.firewall.allowedTCPPorts = [
    3900 # S3 API
    3903 # Garage admin /metrics
  ];
}
