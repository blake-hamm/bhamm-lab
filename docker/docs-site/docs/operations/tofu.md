# Open Tofu (Terraform)

All OpenTofu stacks under `tofu/` use a shared S3 backend on the Ceph RGW cluster (Proxmox-hosted, independent of the Talos clusters).

## State Location

- **Bucket:** `tofu-state` on Ceph RGW
- **Endpoint:** `https://rgw.bhamm-lab.com` (Traefik ingress to RGW nodes `10.0.20.11-13:7480`)
- **Addressing:** path-style, region `main`
- **Bucket declaration:** `kubernetes/manifests/base/ceph/buckets-prod.yaml`

## Credentials

The S3 user is at Vault path `/core/ceph` (keys `s3_access_key` / `s3_secret_key`). Export it before any `tofu init` / `plan` / `apply`:

```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
```

Never put these credentials in git.

## State Layout

| Stack | State key |
|-------|-----------|
| `tofu/proxmox/talos` | `env:/prod/proxmox/talos/terraform.state` (prod workspace) |
| `tofu/proxmox/garage` | `proxmox/garage/terraform.state` |
| `tofu/kubernetes` | `kubernetes/terraform.state` |
| `tofu/gcp` | `gcp/terraform.state` |
| `tofu/cloudflare` | `cloudflare/terraform.state` |
| `tofu/backblaze` | `backblaze/terraform.state` |

## Untracking result/ admin-config artifacts (one-time)

`result/kube-config-*.yaml` / `result/talos-config-*.yaml` are no longer state-tracked (the `local_file` resources were removed; the files are re-mintable from `talos_machine_secrets`, see [Talos](../deployments/talos.md)). If your state still has `local_file` entries for them, run exactly once from a machine with state access, **before the first apply after this change lands** (otherwise that apply will "destroy" them and delete the local files on disk):

```bash
tofu -chdir=tofu/proxmox/talos workspace select prod
tofu -chdir=tofu/proxmox/talos state rm local_file.talos_config
tofu -chdir=tofu/proxmox/talos state rm local_file.kube_config
```

The `state rm` keeps the files on disk and makes subsequent plans quiet.

## One-Time Migration

For each stack, migrate the state from the old backend (the local `terraform.tfstate` file for the local-backend stacks) into the RGW backend:

```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
tofu -chdir=tofu/<stack> init -migrate-state   # accept the migrate prompt
tofu -chdir=tofu/<stack> plan                  # must be empty -> state parity
```

The local-backend stacks upload their local state.

## Provider prerequisites per stack

- **kubernetes:** the stack has no `config_path` for the `kubernetes`/`helm` providers — the shell must point them at a kubeconfig for the target cluster. `KUBECONFIG` alone is NOT sufficient for the `hashicorp/kubernetes` provider: without `KUBE_CONFIG_PATH` the provider falls back to `localhost:80` and plan/apply fails with `dial tcp [::1]:80 connect: connection refused`.

  ```bash
  export KUBE_CONFIG_PATH=tofu/proxmox/talos/result/kube-config-prod.yaml  # re-minted per deployments/talos.md (talos_machine_secrets in state)
  export KUBECONFIG=$KUBE_CONFIG_PATH
  ```

  See `docker/docs-site/docs/deployments/talos.md` for the same convention per environment.
- **gcp:** the `google` provider uses Application Default Credentials locally — run `gcloud auth application-default login` once, then pass `-var project_id=... -var region=...` at plan/apply. CI plans this stack plan-only as `tofu-gcp-plan@deep-contact-445917-i9`; its key lives at Vault kv `external/gcp-cicd` (property `google_credentials`, synced from `secrets.enc.json`) and is exported as `GOOGLE_CREDENTIALS`. The SA holds exactly three read-only predefined roles — `roles/browser` (project + project-policy read), `roles/cloudkms.viewer` (keyring/cryptokey + cryptokey-policy read), `roles/iam.serviceAccountViewer` (SA + SA-key read). `iam.serviceAccountKeys.get` in that last role is load-bearing: without it the provider reads a 403 as "key deleted", drops both managed keys from state, and plans a bogus recreate. `iam.googleapis.com` and `cloudresourcemanager.googleapis.com` must stay enabled on the project — service-account callers get `SERVICE_DISABLED` from both even while a human owner still reads them fine.
- **cloudflare:** pass `-var cloudflare_api_token=... -var cloudflare_account_id=... -var tunnel_secret=...` (values from Vault). CI now plans this stack from the same Vault kv path `external/cloudflare` (keys `terraform-token`, `account-id`, `tunnel_secret`).
- **backblaze:** pass `-var b2_application_key_id=... -var b2_application_key=...` plus the bucket/key name vars (values from Vault).

## Workspace Seeding (talos + kubernetes only)

`tofu/proxmox/talos` and `tofu/kubernetes` switch environments via workspaces (dev/test/prod). For a stack that already used workspaces locally, `tofu init -migrate-state` from the local backend migrates ALL workspaces: it prompts "migrate all workspaces?" and answers yes (`-force-copy` answers without prompting). Every local workspace sidecar is copied to its S3 object and the local sidecars are emptied.

State object layout on the S3 backend:

- Default workspace: the bare key (e.g. `kubernetes/terraform.state`)
- Named workspace `<ws>`: `env:/<ws>/<key>` (literal `env:` prefix, e.g. `env:/dev/kubernetes/terraform.state`)

To work in an environment:

```bash
tofu -chdir=tofu/<stack> workspace select <env>
tofu -chdir=tofu/<stack> plan -var-file=<env>.tfvars
```

A brand-new workspace with no local sidecar simply starts empty — do not apply blindly against it.

**CI pin:** `tofu-cicd` pins `proxmox/talos` plans to the `prod`
workspace automatically (the live cluster state; the tfvars file is
`prod.tfvars` and the workspace is also `prod` — 'green' survives only
in legacy cluster naming, not in workspaces. A missing workspace fails
the run rather than auto-creating empty state). Operators running
talos commands manually must select the workspace themselves — `tofu
workspace show` before anything else. `test` may be onboarded later by
extending the per-stack workspace pin in the workflow.

State may contain secrets — treat local sidecars and S3 objects with care.
