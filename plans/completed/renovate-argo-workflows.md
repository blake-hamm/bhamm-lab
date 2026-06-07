# Renovate via Argo Workflows CronWorkflow

**STATUS: COMPLETED**

Deploy Renovate as a self-hosted bot using an Argo Workflows `CronWorkflow`, keeping all execution within the existing Kubernetes + Argo stack. Renovate scans the `blake-hamm/bhamm-lab` monorepo on Codeberg and opens PRs for dependency updates.

## Target Architecture

- **Execution:** Argo Workflows `CronWorkflow` in namespace `argo`
- **Platform:** Codeberg via Renovate's `gitea` platform module (Forgejo platform unavailable in Renovate v39)
- **Auth:** Dedicated bot account + PAT stored in SOPS → Vault → External Secret
- **Cache:** PVC mounted at `/tmp/renovate/cache` for repo/package metadata between runs
- **Config:** `config.js` injected via ConfigMap; `renovate.json` in repo root
- **Observability:** Argo UI, Prometheus workflow metrics, logs in existing stack
- **GitOps:** Manifests deployed via the existing `automations` ArgoCD Application

---

## Phase 0: Pre-Requisites
**STATUS: COMPLETE**

### 0.1 Create Renovate Bot Account on Codeberg
- Dedicated bot user created
- Full name and email configured in profile

### 0.2 Generate Personal Access Token
Generated full-access PAT with these scopes (repo-scoped PATs do not support `user:read`):

| Scope | Permission | Why |
|-------|-----------|-----|
| `repo` | Read and Write | Clone, create branches, push commits, open/update PRs |
| `user` | Read | Get bot username/email for commits |
| `issue` | Read and Write | Create/update Dependency Dashboard issue |
| `organization` | Read | Read org labels and teams |

### 0.3 Grant Repo Access
Bot added as collaborator to `blake-hamm/bhamm-lab` with **Write** access.

### 0.4 Add Secrets to SOPS
Added `renovate_pat` to `secrets.enc.json` under `vault_secrets.external.codeberg`:

```json
"codeberg": {
  "renovate_pat": "YOUR_CODEBERG_PAT_HERE"
}
```

Encrypted with SOPS and committed. The `sops-vault-sync` Argo WorkflowTemplate pushes to Vault at `secret/external/codeberg`. External Secrets Operator syncs to the cluster.

---

## Phase 1: Kubernetes Manifests
**STATUS: COMPLETE**

The PVC and ExternalSecret are provisioned through the existing `common` Helm chart (used by `argo-common`).

### 1.1 Update `argo-common` Application

Updated `kubernetes/manifests/base/argo/common-all.yaml`:

```yaml
        externalSecrets:
          enabled: true
          secrets:
            - secretKey: renovate-token
              remoteRef:
                key: /external/codeberg
                property: renovate_pat
        pvc:
          - name: renovate-cache
            storageSize: 2Gi
            storageClassName: csi-rbd-sc
```

### 1.2 ConfigMap for Renovate Config

Created `kubernetes/manifests/automations/renovate/renovate-configmap.yaml`:

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
      platform: 'gitea',
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

**Notes:**
- `platform: 'gitea'` used because Renovate's standalone `forgejo` platform was added after v39 (merged July 2025). The `gitea` module is fully compatible with Forgejo.
- `onboarding: true` was used initially to generate the onboarding PR. After merging the onboarding PR, changed to `onboarding: false`.

### 1.3 CronWorkflow

Created `kubernetes/manifests/automations/renovate/renovate-cronworkflow.yaml`:

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
  schedules:
    - "0 1 * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 300
  workflowSpec:
    serviceAccountName: argo-workflow
    entrypoint: renovate
    templates:
      - name: renovate
        container:
          image: renovate/renovate:39.264
          securityContext:
            runAsUser: 0
            runAsGroup: 0
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
- `schedules:` (array) used instead of `schedule:` (string) — Argo Workflows v4.0.4 API
- `concurrencyPolicy: Forbid` prevents overlapping runs
- Cache PVC avoids re-cloning and re-fetching package metadata on every run
- Image pinned to `39.264` for reproducibility
- Container runs as root (`runAsUser: 0`) to avoid UID fragility — Renovate v39 uses UID 12021, which may change in future versions

---

## Phase 2: GitOps Registration
**STATUS: COMPLETE**

The `automations` ArgoCD Application watches `kubernetes/manifests/automations/` recursively. No new Application needed. ArgoCD auto-synced the new manifests.

---

## Phase 3: First Run & Onboarding
**STATUS: COMPLETE**

### 3.1 Trigger Manually
```bash
argo submit --from cronworkflow/renovate -n argo
```

### 3.2 Monitor Logs
```bash
argo logs -n argo -l workflows.argoproj.io/workflow=$(argo list -n argo | grep renovate | head -1 | awk '{print $1}')
```

### 3.3 Onboarding PR
Renovate generated an onboarding PR on Codeberg with a default `renovate.json`. After merging the onboarding PR, the feature branch was rebased and `onboarding: false` was set in `config.js`.

### 3.4 Verify PR Creation
Subsequent runs open PRs for outdated dependencies. Check:
- Codeberg PRs tab
- Dependency Dashboard issue (created automatically)

---

## Phase 4: Post-Deploy Tuning
**STATUS: COMPLETE**

### 4.1 Custom renovate.json in Repo

`renovate.json` at repo root:

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
  "pinDigests": false,
  "labels": ["dependencies"],
  "kubernetes": {
    "fileMatch": ["^kubernetes/manifests/.+\\.yaml$"]
  }
}
```

**Notes:**
- `automerge: false` — every PR requires manual review and approval
- `pinDigests: false` — use human-readable version tags instead of SHA digests
- `kubernetes.fileMatch` — enables Renovate's `kubernetes` manager for container images in raw YAML manifests (the manager has no default file patterns)

### 4.2 GitHub Rate-Limit Token (optional)
Not implemented. Can be added later if changelog lookups hit GitHub rate limits.

---

## Phase 5: Documentation Update
**STATUS: COMPLETE**

Updated `docker/docs-site/docs/`:
- `architecture/index.md` — Added Renovate to automation list
- `index.md` — Crossed out mid-term Renovate goal
- `security/index.md` — Moved Renovate from "Future" to "Current"

---

## Files Created

```
kubernetes/manifests/automations/renovate/
├── renovate-configmap.yaml
└── renovate-cronworkflow.yaml
renovate.json                          # repo root
```

## Files Updated

- `kubernetes/manifests/base/argo/common-all.yaml` — Added `renovate-token` external secret and `renovate-cache` PVC
- `secrets.enc.json` — Added `vault_secrets.external.codeberg.renovate_pat`
- `kubernetes/manifests/base/argo/automations-all.yaml` — Temporarily switched `targetRevision` to `feature/renovate`, then reverted to `main`
- `docker/docs-site/docs/architecture/index.md` — Added Renovate to automation list
- `docker/docs-site/docs/index.md` — Marked renovate as complete in mid-term goals
- `docker/docs-site/docs/security/index.md` — Marked renovate as complete in future goals

---

## Execution Checklist

- [x] Phase 0: Create Renovate bot account on Codeberg with full name + email
- [x] Phase 0: Generate PAT with `repo`, `user`, `issue`, `organization` scopes
- [x] Phase 0: Grant bot Write access to `blake-hamm/bhamm-lab` repo
- [x] Phase 0: Add `renovate_pat` to `secrets.enc.json` under `vault_secrets.external.codeberg` and encrypt
- [x] Phase 0: Commit and push `secrets.enc.json` to trigger `sops-vault-sync` workflow
- [x] Phase 1: Update `kubernetes/manifests/base/argo/common-all.yaml` with renovate external secret and PVC
- [x] Phase 1: Create `kubernetes/manifests/automations/renovate/` directory with ConfigMap and CronWorkflow
- [x] Phase 1: Verify ConfigMap and CronWorkflow syntax
- [x] Phase 2: Commit and push manifests
- [x] Phase 2: Verify ArgoCD syncs new manifests to `argo` namespace
- [x] Phase 3: Trigger manual run: `argo submit --from cronworkflow/renovate -n argo`
- [x] Phase 3: Monitor workflow logs for errors
- [x] Phase 3: Verify dependency update PRs are created on subsequent runs
- [x] Phase 4: Create `renovate.json` in repo root
- [x] Phase 5: Update docs-site with Renovate documentation
- [x] Phase 5: Run `pre-commit` before final commit
