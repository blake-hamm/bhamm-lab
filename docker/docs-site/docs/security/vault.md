# Vault


## `kubernetes/core/vault/cr-raft.yaml`
This file defines the config that vault operator applies to our vault instance. More details found here:

 - https://bank-vaults.dev/docs/concepts/external-configuration/
 - https://github.com/bank-vaults/vault-operator/tree/main/deploy/examples
 - https://github.com/bank-vaults/vault-operator/tree/main/test/deploy

To login to the vault cli run:
```bash
vault login -method=oidc role=default
```

## Kubernetes auth roles

Workloads authenticate to Vault through the `auth/kubernetes` mount: a
pod's service-account token is exchanged for a Vault token
(`POST /v1/auth/kubernetes/login`). The roles live in the Vault CR's
`externalConfig.auth` (`kubernetes/manifests/base/vault/cr-all.yaml`):

- `sops` — bound to the `argo-workflow` SA in the `argo` namespace; the
  Argo workflow that syncs SOPS-decrypted secrets into Vault.
- `ci` — bound to the `git-actions-forgejo-runner` SA in the
  `git-actions` namespace; read-only (`ci_secrets`) on the four secret
  paths the Forgejo CI smoke workflow reads (see the "Vault
  credentials" section in `operations/ci-validation.md`).
