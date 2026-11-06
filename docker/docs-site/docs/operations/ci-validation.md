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
| `ansible` | `ansible-galaxy install -r ansible/requirements.yml`, `ansible-playbook --syntax-check ansible/main.yml` (via `uv`, `ansible-core>=2.19,<2.20` — prometheus.prometheus 0.29.1 caps ansible-core at ≤2.20.99) | uv |
| `image-digests` | `crane digest` on every `image:` ref in `kubernetes/manifests` — the #1 renovate failure mode (unpullable digest/tag); pulls are authenticated via optional GHCR/Docker Hub creds (Forgejo secrets) and throttles (429/401) get a bounded retry (3 attempts) | crane |

**Pin of record:** the top-level `env:` block in
`.forgejo/workflows/validate.yml`. Bump a version there and the matching
download step follows. Terraform tool pins (OpenTofu, tflint, trivy) live
in `tofu-cicd.yml` — terraform gates run on terraform changes only. `KUBE_VERSION` must stay in sync with
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
  `secret/data/core/ceph`, `secret/data/core/orangepi`,
  `secret/data/external/proxmox`, `secret/data/external/cloudflare`,
  `secret/data/external/opnsense`, `secret/data/external/backblaze-admin`,
  and `secret/data/external/gcp-cicd` (kv v2 data paths, all synced from
  `secrets.enc.json` by the SOPS → Vault workflow; `external/gcp-cicd`
  holds the plan-only GCP SA key at property `google_credentials`).
- **Smoke gate:** login succeeds, all four paths return non-empty, and
  `tofu init` + `tofu plan` against the proof stack
  (`tofu/proxmox/garage` — SOPS-free, every variable defaulted except
  `proxmox_url`) succeed using
  `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (ceph) and
  `PROXMOX_VE_USERNAME`/`PROXMOX_VE_PASSWORD` (proxmox) exported from
  those reads. A non-empty plan is expected and must not fail the run.
  `proxmox_url` is pinned to `https://10.0.30.11:8006` in the workflow: the
  job runs in a pod, and a routed pod → VLAN 20 Proxmox API call is silently
  black-holed (see [Network & MTU](../architecture/network.md)).
- **Running it:** Actions tab → `ci-vault-smoke` → *Run workflow*.
  Rollout note: the workflow has no push trigger, so feature branches
  get zero runs — run it manually from `main` post-merge.

## Tofu CI pipeline (`tofu-cicd`)

The `tofu-cicd` workflow (`.forgejo/workflows/tofu-cicd.yml`) is the
terraform pipeline: **fmt → lint → plan → apply**. It fires on **every**
branch push (plus `workflow_dispatch` with a `stacks` input, and a
`create` event that owns branch-creation gating) — not because the work
is needed everywhere, but because a required status pattern that never
posts reads as *missing* on Forgejo and blocks merges forever, so exactly
one cheap context must land on every SHA (see
[Commit statuses and automerge policy](#commit-statuses-and-automerge-policy)).
The heavy stages stay internally gated on the detect output, so a
tofu-clean push costs one small detect job + one status post.

- **Stack detection:** a detect job asks the Codeberg compare API which
  files changed (the Forgejo mirror's compare endpoint 404s for
  anonymous and token access alike) and maps them to stack dirs; new
  branches, force-pushes, or compare failures fall back to all known
  stacks. Dispatch input overrides. A changed `tofu/**` file that
  matches no known stack dir — `tofu/.terraform-version` (the pin of
  record: bumping it changes the planner itself), shared modules — is
  treated as touching **every** enabled stack: full plan coverage across
  all stacks is the evidence for shared changes.
- **fmt + lint run for every `KNOWN_STACKS` stack** whose directory
  changed — these stages are stateless (`tofu init -backend=false`, no
  creds) so they cover cloudflare/talos/gcp/kubernetes today, giving
  renovate provider PRs their gate even before those stacks are planable
  in CI.
- **plan runs only for `ENABLED_STACKS`** (see `ENABLED_STACKS` in
  `.forgejo/workflows/tofu-cicd.yml` — the workflow env block is the
  source of truth):
  Vault kubernetes auth role `ci` (same plumbing as `ci-vault-smoke`),
  `tofu init` against the real RGW S3 backend, `tofu plan
  -detailed-exitcode` with **rc 0 and rc 2 both passing** — the gate
  proves the plan *computes* with real state and creds; a non-empty plan
  on a PR branch is expected. CI creds come from the role `ci` Vault
  paths: `core/ceph` (S3 backend), `external/proxmox`,
  `external/backblaze-admin`, `external/cloudflare`, `core/orangepi`
  (`nut_password` for `proxmox/talos`), and `external/gcp-cicd`
  (`GOOGLE_CREDENTIALS` for `gcp`). **apply follows plan for
  `APPLY_STACKS` on PR pushes** (currently all five ENABLED stacks:
  `proxmox/garage`, `backblaze`, `cloudflare`, `proxmox/talos`, `gcp`):
  after the plan stage succeeds, the saved plan file is
  applied — the PR is the deployment, and the allow-list is the
  blast-radius control (it grows one trusted stack at a time). A
  plan-enabled stack that is not in `APPLY_STACKS` records `plan-only`
  and skips apply. `proxmox/talos` enrolled in the apply allow-list
  after its CI plans proved stable; its cluster VMs carry
  `prevent_destroy` so a CI apply cannot destroy them. talos CI plans
  run against OpenTofu workspace `prod` (the live
  cluster state), and a missing workspace fails the run loud rather than
  auto-creating empty state. A non-empty plan on `main` post-merge means
  unmerged branch work diverged from main — a drift signal. Onboarding a
  stack to the plan stage = one `ENABLED_STACKS` entry + one
  credential-map case (+ a `ci_secrets` policy line when a new Vault
  path is needed.
- **No PR comments:** the pipeline posts commit statuses only — no
  marker comments on the PR. The full plan and apply logs live in the
  run logs (linked from each status). A missing `CODEBERG_TOKEN`
  secret fails the run loudly, and `main` pushes post no statuses.
- **Rollout:** workflow files only run once on `main`. Post-merge proof:
  Actions tab → `tofu-cicd` → *Run workflow* (stacks=`auto`), and
  observe natural runs on the next pushes that touch `tofu/**` (e.g.
  renovate terraform-provider PRs).

### Commit statuses and automerge policy

Both gates publish Codeberg **commit statuses** on branch pushes:
`ci/validate` from the validate workflow, and from tofu-cicd either one
`cicd/tofu:<stack>` context per **touched plan-enabled stack** or — on a
push whose diff touches nothing under `tofu/` — exactly one
`cicd/tofu:no-changes` (success, "no tofu changes - nothing to plan").
A SHA that touches tofu posts only its per-stack verdicts, never the
no-changes context. The no-changes post exists because Forgejo's branch
protection treats a required glob that matches zero statuses as pending
forever: `cicd/tofu:**` must find a match on every SHA for automerge and
non-admin merges to ever proceed. Statuses are quiet by design: a stack
posts only when the change actually touched it — `plan ok` (plan-only or
no changes), `plan ok; applied` (apply ran), or a failure description.
Untouched stacks post nothing, and there is no
`unmapped` context: shared/unmapped tofu files (including
`.terraform-version`) replan every enabled stack instead. Statuses are
**pending-first**: on a tofu-touching push, right after detection the run
claims `pending` ("plan in progress") for every context it will
finalize, before any plan work starts — so a run killed mid-pipeline
leaves pending (never green) contexts. Branch protection requires the
patterns `ci/validate` and `cicd/tofu:**`.

`renovate.json` keys its terraform-manager automerge policy on those
required contexts (automerge fires only when every matched required
context is success): provider/core **patch/minor** bumps outside 0.x
pinning merge automatically (squash) once every context is green;
**majors** and any change under the cluster-core talos path are labeled
`risk-high` and held for review; 0.x provider bumps (Renovate classes
them minor, but 0.x minors are breaking-class) hold as `risk-med`.
Everything outside the terraform managers keeps today's never-automerge
behavior. The OpenTofu core version itself is pinned in
`tofu/.terraform-version`, which the CI reads as its pin of record.

## Deliberate exclusions

- **`tofu-cicd` excludes the `kubernetes` stack from plan/apply**: that
  stack *is* the sops/Vault consumer (chicken-and-egg); planning it
  would need a prod-cluster kubeconfig CI deliberately does not hold, and
  its value is lowest since it rarely changes. It still gets fmt/lint
  coverage via `KNOWN_STACKS`.
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
  CI has no harbor creds (skipped by design). `.ci/digest-exceptions.txt`
  tracks dead/renovate-ignore-candidate upstreams and must trend to empty.
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

## Not yet gated

- `ansible-playbook --check` and `nix flake check` gates are not implemented yet.
