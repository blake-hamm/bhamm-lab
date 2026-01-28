{ pkgs, inputs }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    pre-commit
    vault
    kubectl
    kubernetes-helm
    argo-workflows
    argocd
    k9s
    colmena
    poetry
    sops
    mkdocs
    ansible
    ansible-lint
    sshpass
    opentofu
    terraform
    tflint
    trivy
    terrascan
    restic
    openssl
    google-cloud-sdk
    velero
    cilium-cli
    hubble
    talosctl
    uv
    ceph-client
    minio-client
    awscli
    smartmontools
    rclone
    wl-clipboard
    inputs.nixos-anywhere.packages.${pkgs.system}.default
    hugo
  ];

  packages = [
    (pkgs.python3.withPackages (python-pkgs: [
      python-pkgs.mkdocs-material
      python-pkgs.hvac
      python-pkgs.httpx
      python-pkgs.jmespath
    ]))
  ];

  shellHook = ''
    # Install ansible galaxy requirements
    ansible-galaxy install -r ansible/requirements.yml

    # Source .env file if it exists
    if [ -f .env ]; then
      export $(grep -v '^#' .env | xargs)
    fi

    # Define python interpreter for ansible
    export NIX_PYTHON_INTERPRETER=$(which python)

    # Install pre commit
    pre-commit install

    # Define sops key location
    export SOPS_GCP_KMS_ARN=projects/deep-contact-445917-i9/locations/us-central1/keyRings/sops-key-ring/cryptoKeys/sops-key
  '';
}
