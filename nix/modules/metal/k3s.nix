{ pkgs, host, config, lib, ... }:
{
  # Sops secret for token
  sops.secrets.k3s_token = { };

  systemd.enableUnifiedCgroupHierarchy = false;
  services.k3s = {
    enable = true;
    clusterInit = true;
    role = "server";
    extraFlags = toString [
      "--debug"
      "--disable=traefik"
      "--disable=servicelb"
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable=local-storage"
      "--tls-san=192.168.69.20" # Also configured in kube-vip
      "--cluster-cidr=10.42.0.0/16" # Also configured in calico.yaml
      "--kube-proxy-arg=ipvs-strict-arp=true" # Required for metallb
    ];
    serverAddr = "https://192.168.69.20:6443";
    tokenFile = config.sops.secrets.k3s_token.path;
  };
  environment.systemPackages = with pkgs; [
    k3s
    argocd
    kubernetes-helm
    nfs-utils
    ceph
  ];
  networking.firewall.enable = lib.mkForce false; # Must be disabled for calico
  # TODO: fine grain firewall

}
