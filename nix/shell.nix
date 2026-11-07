{ pkgs, inputs }:
pkgs.mkShell {
  packages = with pkgs; [
    pre-commit
    vault
    kubectl
    kubernetes-helm
    argo-workflows
    argocd
    k9s
    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
    poetry
    sops
    ansible
    ansible-lint
    sshpass
    opentofu
    terraform
    tflint
    trivy
    restic
    openssl
    google-cloud-sdk
    velero
    cilium-cli
    hubble
    talosctl
    ceph-client
    minio-client
    awscli
    smartmontools
    rclone
    wl-clipboard
    inputs.nixos-anywhere.packages.${pkgs.stdenv.hostPlatform.system}.default
    hugo
    # mkdocs itself comes from the python environment below
    (python3.withPackages (python-pkgs: [
      python-pkgs.mkdocs-material
      python-pkgs.hvac
      python-pkgs.httpx
      python-pkgs.jmespath
    ]))
  ];

  shellHook = ''
    # Install ansible galaxy requirements, but only when the file changed
    stamp=.git/ansible-galaxy.stamp
    if [ ! -f "$stamp" ] || [ ansible/requirements.yml -nt "$stamp" ]; then
      ansible-galaxy install -r ansible/requirements.yml && touch "$stamp"
    fi

    # Define python interpreter for ansible
    export NIX_PYTHON_INTERPRETER=$(which python)

    # Install pre commit
    pre-commit install

    # Define sops key location
    export SOPS_GCP_KMS_ARN=projects/deep-contact-445917-i9/locations/us-central1/keyRings/sops-key-ring/cryptoKeys/sops-key
  '';
}
