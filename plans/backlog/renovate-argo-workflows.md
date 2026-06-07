# Renovate via Argo Workflows CronWorkflow

## Objective
Deploy Renovate as a self-hosted bot using an Argo Workflows `CronWorkflow`, keeping all execution within the existing Kubernetes + Argo stack. Renovate will scan the `blake-hamm/bhamm-lab` monorepo on Codeberg and automatically open PRs for dependency updates.

## Target Architecture
- **Execution:** Argo Workflows `CronWorkflow` in namespace `argo`
- **Platform:** Codeberg (Forgejo) via Renovate's `forgejo` platform module
- **Auth:** Dedicated bot account + PAT stored in SOPS → Vault → External Secret
- **Cache:** PVC mounted at `/tmp/renovate/cache` for repo/package metadata between runs
- **Config:** `config.js` injected via ConfigMap or env vars
- **Observability:** Argo UI, Prometheus workflow metrics (already enabled), logs in existing stack
- **GitOps:** Manifests deployed via the existing `automations` ArgoCD Application

---

## Phase 0: Pre-Requisites
**STATUS: PENDING**

### 0.1 Create Renovate Bot Account on Codeberg
- Register dedicated bot user (e.g., `bhamm-renovate`)
- Configure **full name** and **email** in profile — required for git commits

### 0.2 Generate Personal Access Token
Generate PAT for bot with these scopes:

| Scope | Permission | Why |
|-------|-----------|-----|
| `repo` | Read and Write | Clone, create branches, push commits, open/update PRs |
| `user` | Read | Get bot username/email for commits |
| `issue` | Read and Write | Create/update Dependency Dashboard issue |
| `organization` | Read | Read org labels and teams |

### 0.3 Grant Repo Access
Add bot as collaborator to `blake-hamm/bhamm-lab` with **Write** access.

### 0.4 Add Secrets to SOPS
Add the Renovate PAT to `secrets.enc.json` under `.vault_secrets.external.codeberg`:

```json
"codeberg": {
  "renovate_token": "YOUR_CODEBERG_PAT_HERE"
}
```

Then encrypt and commit:
```bash
sops --encrypt --in-place secrets.enc.json
```

The `sops-vault-sync` Argo WorkflowTemplate (already running on push) will decrypt and push these to Vault at `secret/external/codeberg`. External Secrets Operator then syncs them to the cluster.

---

## Phase 1: Kubernetes Manifests
**STATUS: PENDING**

The PVC and ExternalSecret are provisioned through the existing `common` Helm chart (used by `argo-common`). This keeps them consistent with the rest of the stack and provides standard benefits like k8up backup annotations and uniform secret management.

### 1.1 Update `argo-common` Application

Add Renovate entries to `kubernetes/manifests/base/argo/common-all.yaml`:

```yaml
        externalSecrets:
          enabled: true
          secrets:
            # ... existing secrets ...
            - secretKey: forgejo-token
              remoteRef:
                key: /core/argo-workflows
                property: forgejo-token
            - secretKey: renovate-token
              remoteRef:
                key: /external/codeberg
                property: renovate_token
        pvc:
          - name: renovate-cache
            storageSize: 5Gi
            storageClassName: csi-rbd-sc
```

### 1.2 ConfigMap for Renovate Config

Create `kubernetes/manifests/automations/renovate/renovate-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: renovate-config
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "1"
data:
  config.js: |
    module.exports = {
      platform: 'forgejo',
      endpoint: 'https://codeberg.org/api/v1',
      repositories: ['blake-hamm/bhamm-lab'],
      onboarding: false,
      dependencyDashboard: true,
      gitAuthor: 'Renovate Bot <renovate@bhamm-lab.com>',
      automerge: false,
      labels: ['dependencies'],
      extends: [
        'config:best-practices',
        ':dependencyDashboard',
        ':gitSignOff',
        ':semanticCommits',
        ':semanticCommitTypeAll(chore)',
      ],
    };
```

**Note:** Set `platform: 'forgejo'` explicitly. Codeberg runs Forgejo, and Renovate is deprecating `gitea` platform support.

### 1.3 CronWorkflow

Create `kubernetes/manifests/automations/renovate/renovate-cronworkflow.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: renovate
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "2"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  schedule: "0 */4 * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 300
  workflowSpec:
    serviceAccountName: argo-workflow
    entrypoint: renovate
    templates:
      - name: renovate
        container:
          image: renovate/renovate:39
          env:
            - name: RENOVATE_CONFIG_FILE
              value: /opt/renovate/config.js
            - name: RENOVATE_TOKEN
              valueFrom:
                secretKeyRef:
                  name: argo-external-secret
                  key: renovate-token
            - name: LOG_LEVEL
              value: info
          volumeMounts:
            - name: renovate-config
              mountPath: /opt/renovate
            - name: renovate-cache
              mountPath: /tmp/renovate/cache
          resources:
            requests:
              memory: 512Mi
              cpu: 250m
            limits:
              memory: 2Gi
              cpu: 1000m
    volumes:
      - name: renovate-config
        configMap:
          name: renovate-config
      - name: renovate-cache
        persistentVolumeClaim:
          claimName: renovate-cache
```

**Notes:**
- `concurrencyPolicy: Forbid` prevents overlapping runs if a scan takes >4 hours
- Cache PVC avoids re-cloning and re-fetching package metadata on every run
- Platform and endpoint are set in `config.js` only — env vars would override and create confusion
- Memory request is conservative (512Mi); bump to 1Gi if first run OOMKills
- Adjust `schedule` as needed (e.g., `"0 6 * * *"` for daily at 6 AM)

---

## Phase 2: GitOps Registration
**STATUS: PENDING**

The `automations` ArgoCD Application already watches `kubernetes/manifests/automations/` recursively. No new Application needed.

Create the folder and files, commit, push. ArgoCD will auto-sync.

---

## Phase 3: First Run & Onboarding
**STATUS: PENDING**

### 3.1 Trigger Manually
```bash
argo submit --from cronworkflow/renovate -n argo
```

Or via Argo UI: Cron Workflows → renovate → Submit.

### 3.2 Monitor Logs
```bash
argo logs -n argo -l workflows.argoproj.io/workflow=$(argo list -n argo | grep renovate | head -1 | awk '{print $1}')
```

### 3.3 Verify PR Creation
With `onboarding: false` in config.js and `renovate.json` already in repo root (Phase 4.1), runs should open PRs for outdated dependencies. Check:
- Codeberg PRs tab
- Dependency Dashboard issue (created automatically if `dependencyDashboard: true`)

---

## Phase 4: Post-Deploy Tuning
**STATUS: PENDING**

### 4.1 Custom renovate.json in Repo
**Create before first run.** With `onboarding: false`, Renovate expects this file to exist in the repo. Add `renovate.json` to repo root:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:best-practices",
    ":dependencyDashboard",
    ":gitSignOff",
    ":semanticCommits",
    ":semanticCommitTypeAll(chore)"
  ],
  "automerge": false,
  "labels": ["dependencies"],
  "packageRules": [
    {
      "matchUpdateTypes": ["minor", "patch"],
      "matchCurrentVersion": "!/^0/",
      "automerge": true
    }
  ]
}
```

### 4.2 Add GitHub Rate-Limit Token (optional)
For changelog/release note lookups without hitting GitHub rate limits:
- Generate GitHub PAT with `public_repo` scope
- Add to SOPS/Vault/External Secret as `gh_token`
- Set `RENOVATE_GITHUB_TOKEN` env var in CronWorkflow

---

## Phase 5: Documentation Update
**STATUS: PENDING**

Update `docker/docs-site/docs/`:
- Add Renovate to architecture/automation section
- Document bot account setup, PAT scopes, and manual trigger command
- Update `docker/docs-site/docs/index.md` mid-term goals (mark renovate complete)

---

## Files to Create

```
kubernetes/manifests/automations/renovate/
├── renovate-configmap.yaml
└── renovate-cronworkflow.yaml
renovate.json                          # repo root — create before first run
```

## Files to Update

- `kubernetes/manifests/base/argo/common-all.yaml` — Add `renovate-token` external secret and `renovate-cache` PVC
- `secrets.enc.json` — Add `vault_secrets.external.codeberg.renovate_token` entry
- `docker/docs-site/docs/architecture/index.md` — Add Renovate to automation list
- `docker/docs-site/docs/index.md` — Mark renovate as complete in mid-term goals
- `docker/docs-site/docs/security/index.md` — Mark renovate as complete in future goals
- `renovate.json` — repo root, create before first run

---

## Execution Checklist

- [ ] Phase 0: Create Renovate bot account on Codeberg with full name + email
- [ ] Phase 0: Generate PAT with `repo`, `user`, `issue`, `organization` scopes
- [ ] Phase 0: Grant bot Write access to `blake-hamm/bhamm-lab` repo
- [ ] Phase 0: Add `renovate_token` to `secrets.enc.json` under `vault_secrets.external.codeberg` and encrypt
- [ ] Phase 0: Commit and push `secrets.enc.json` to trigger `sops-vault-sync` workflow
- [ ] Phase 1: Update `kubernetes/manifests/base/argo/common-all.yaml` with renovate external secret and PVC
- [ ] Phase 1: Create `kubernetes/manifests/automations/renovate/` directory with ConfigMap and CronWorkflow
- [ ] Phase 1: Verify ConfigMap and CronWorkflow syntax
- [ ] Phase 2: Commit and push manifests
- [ ] Phase 2: Verify ArgoCD syncs new manifests to `argo` namespace
- [ ] Phase 4: Create `renovate.json` in repo root (must exist before first run)
- [ ] Phase 3: Trigger manual run: `argo submit --from cronworkflow/renovate -n argo`
- [ ] Phase 3: Monitor workflow logs for errors
- [ ] Phase 3: Verify dependency update PRs are created on subsequent runs
- [ ] Phase 5: Update docs-site with Renovate documentation
- [ ] Phase 5: Run `pre-commit` before final commit
