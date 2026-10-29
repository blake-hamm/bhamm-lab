# CI Validation Layer

Every push to the [Forgejo mirror](https://git.bhamm-lab.com) runs the
`validate` workflow (`.forgejo/workflows/validate.yml`) — visible in the
**Actions** tab of the Forgejo UI. The Forgejo repo is a mirror of Codeberg:
a Codeberg webhook triggers an immediate mirror sync, which fires a **push**
event. `pull_request` never fires on a mirror, so there is no PR signal —
a push to any branch (including feature and renovate branches) is the CI
signal, and `workflow_dispatch` allows manual runs.

All jobs run on the self-hosted dind runner (`runs-on: docker`) in a
`docker.io/alpine:3.20` container, in parallel, with no external action
dependencies: each job installs its tools from pinned release URLs, checks
out the tree via the Forgejo archive endpoint, and runs its gates.

## Jobs

| job | what it checks | tools (pins) |
| --- | --- | --- |
| `lint` | `yamlfmt -lint .`, `shfmt -d -s -i 2` on every `*.sh`, trailing whitespace, tabs, CRLF | yamlfmt, shfmt |
| `secrets` | `gitleaks detect --no-git --redact` (tree scan), `ripsecrets` over the tree | gitleaks, ripsecrets |
| `k8s-schemas` | `kubeconform -strict -ignore-missing-schemas` over `kubernetes/manifests` | kubeconform |
| `open-tofu` | `tofu fmt -check`, `tofu init -backend=false` + `tofu validate` + `tflint` per env, `trivy config` | opentofu, tflint, trivy |
| `ansible` | `ansible-galaxy install -r ansible/requirements.yml`, `ansible-playbook --syntax-check ansible/main.yml` (via `uv`, `ansible-core>=2.19,<2.20` — prometheus.prometheus 0.29.1 caps ansible-core at ≤2.20.99) | uv |
| `image-digests` | `crane digest` on every `image:` ref in `kubernetes/manifests` — the #1 renovate failure mode (unpullable digest/tag); pulls are authenticated via optional GHCR/Docker Hub creds (Forgejo secrets) and throttles (429/401) get a bounded retry (3 attempts) | crane |

**Pin of record:** the top-level `env:` block in
`.forgejo/workflows/validate.yml`. Bump a version there and the matching
download step follows. `KUBE_VERSION` must stay in sync with
`talos_version` in `tofu/proxmox/talos/variables.tf` (Talos v1.12.6 →
k8s 1.35).

## Vault credentials

The `ci-vault-smoke` workflow
(`.forgejo/workflows/ci-vault-smoke.yml`, `workflow_dispatch` only)
proves the Vault → CI credential plumbing end to end.

- **Auth:** the runner pod's service-account token is exchanged for a
  Vault token via the `auth/kubernetes` mount, role `ci`
  (`POST /v1/auth/kubernetes/login`), against `https://vault.vault:8200`
  with `VAULT_SKIP_VERIFY=true`. The token reaches the job container
  because job containers run via the dind sidecar (not as k8s pods):
  the pod SA token is auto-mounted into every pod container including
  dind, and a read-only `-v` bind in the runner's `container.options`
  (see `kubernetes/manifests/core/forgejo/runner-helm-prod.yaml`) exposes
  it to the job container.
- **Role `ci`:** bound to the `git-actions-forgejo-runner` SA in the
  `git-actions` namespace, policy `ci_secrets`, token TTL 1h. Defined in
  `kubernetes/manifests/base/vault/cr-all.yaml` (`externalConfig.auth`),
  applied by the bank-vaults configurer on Argo sync.
- **Policy `ci_secrets`:** read+list on exactly
  `secret/data/core/ceph`, `secret/data/external/proxmox`,
  `secret/data/external/cloudflare`, `secret/data/external/opnsense`
  (kv v2 data paths; the underlying keys are synced from
  `secrets.enc.json` by the SOPS → Vault workflow).
- **Smoke gate:** login succeeds, all four paths return non-empty, and
  `tofu init` + `tofu plan` against the proof stack
  (`tofu/proxmox/garage` — SOPS-free, every variable defaulted) succeed
  using `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (ceph) and
  `PROXMOX_VE_USERNAME`/`PROXMOX_VE_PASSWORD` (proxmox) exported from
  those reads. A non-empty plan is expected and must not fail the run.
- **Running it:** Actions tab → `ci-vault-smoke` → *Run workflow*.
  Rollout note: the workflow has no push trigger, so feature branches
  get zero runs — run it manually from `main` post-merge.

## Deliberate exclusions

- **gitleaks: tree scan, never history.** 7 stale hits live in old commits
  by design (the fixes are in the tree; history is immutable). The
  `.gitleaks.toml` allowlist covers the 7 tree-scan false positives — all
  ExternalSecret key-NAME references or OpenTofu provider variable wiring,
  no real secret values.
- **yamlfmt excludes `kubernetes/charts`**: helm template output is not
  parseable YAML. (The pre-commit hook never saw these files because it
  only scans touched files.)
- **ripsecrets excludes `ansible/roles/opnsense/tasks/wireguard.yml`**:
  WireGuard **public** key false positive.
- **kubeconform `-ignore-missing-schemas`**: ~23 CRD kinds lack core
  schemas (Application, Certificate, CiliumNetworkPolicy, ClusterIssuer,
  Middleware, Vault, Workflow, Kustomization, ...).
- **image-digests skips `harbor.bhamm-lab.com` refs**: private registry;
  CI creds arrive later (S4). `.ci/digest-exceptions.txt` tracks
  dead/renovate-ignore-candidate upstreams and must trend to empty.
- **tab check excludes `.gitmodules`**: it legitimately contains tabs.

## Case study: dead upstreams caught on day one

The `image-digests` gate's first run surfaced two dead upstreams that had
been silently broken in the tree:

- **`minio/mc`** — MinIO stopped publishing community images and the
  registry ref 404s. Replaced with `cgr.dev/chainguard/minio-client`
  (maintained drop-in; the binary inside is still `mc`, so commands and
  env are unchanged).
- **`ghcr.io/plexguide/huntarr`** — the Huntarr.io project ended (Feb 2026) and
  the ghcr ref returns 403. No verified drop-in successor exists yet
  (`huntarr/plexguide` on Docker Hub is the PlexGuide platform, not Huntarr —
  its OCI labels prove it), so the deployment is left pointing at the dead ref
  and listed in `.ci/digest-exceptions.txt` — the app only survives on cached
  image pulls and will fail on a fresh node. Successor decision pending (fork
  candidate: `ghcr.io/elfhosted/newtarr`).

The minio/mc replacement landed in the same PR as the gate — exactly the
failure mode (renovate pointing at an unpullable image) the gate exists to
catch. The huntarr case is the deliberate exception-list path.

**Why the gate authenticates:** ghcr.io throttles anonymous manifest
requests per egress IP, and the twin smoke+validate runs double the
request count — anonymous pulls from the runner began getting
UNAUTHORIZED (2026-10-29). The `GHCR_TOKEN`/`GHCR_USERNAME` and
`DOCKERHUB_USER`/`DOCKERHUB_TOKEN` Forgejo secrets are optional: a
missing or failed login degrades to anonymous pulls and never reddens
CI.

## Landing later

- **#322** — `tofu plan` gate (needs S4 Vault creds).
- **#323** — `ansible-playbook --check`.
- **#324** — nix gate.
