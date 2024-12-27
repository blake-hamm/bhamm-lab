{ pkgs }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    pre-commit
    vault
    kubectl
    kubernetes-helm
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
  '';
}
