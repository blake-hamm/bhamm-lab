# Renovate via Argo Workflows CronWorkflow

## Objective
Deploy Renovate as a self-hosted bot using an Argo Workflows `CronWorkflow`, keeping all execution within the existing Kubernetes + Argo stack. Renovate will scan the `bhamm-lab/bhamm-lab` monorepo on Codeberg and automatically open PRs for dependency updates.

## Target Architecture
- **Execution:** Argo Workflows `CronWorkflow` in namespace `argo`
- **Platform:** Codeberg (Forgejo) via Renovate's `forgejo` platform module
- **Auth:** Dedicated bot account + PAT stored in Vault → External Secret
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
Add bot to `bhamm-lab` organization team with **Write** access to target repos, or add as direct collaborator.

### 0.4 Generate SSH Signing Key (optional but recommended)
```bash
ssh-keygen -t ed25519 -C "renovate@bhamm-lab.com" -f renovate_signing_key -N ""
```
- Add **public** key to bot's Codeberg profile under SSH/GPG Keys > Signing Keys
- Save **private** key for Vault/External Secret

### 0.5 Add Secrets to Vault
Add these keys to the Vault path for Argo Workflows:
- `renovate_token` — Codeberg PAT
- `renovate_ssh_private_key` — SSH signing private key (optional)

---

## Phase 1: Kubernetes Manifests
**STATUS: PENDING**

### 1.1 External Secret

Create `kubernetes/manifests/automations/renovate/renovate-external-secret.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: renovate-external-secret
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: renovate-external-secret
    creationPolicy: Owner
  data:
    - secretKey: token
      remoteRef:
        key: /core/renovate
        property: renovate_token
    - secretKey: ssh-private-key
      remoteRef:
        key: /core/renovate
        property: renovate_ssh_private_key
```

### 1.2 PVC for Cache

Create `kubernetes/manifests/automations/renovate/renovate-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: renovate-cache
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: ceph-block
```

### 1.3 ConfigMap for Renovate Config

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
      repositories: ['bhamm-lab/bhamm-lab'],
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

### 1.4 CronWorkflow

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
                  name: renovate-external-secret
                  key: token
            - name: RENOVATE_PLATFORM
              value: forgejo
            - name: RENOVATE_ENDPOINT
              value: https://codeberg.org/api/v1
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

### 3.3 Onboarding PR
First successful run opens an **onboarding PR** in `bhamm-lab/bhamm-lab` proposing a `renovate.json` file:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["local>bhamm-lab/bhamm-lab//.github/renovate"]
}
```

Merge the onboarding PR to enable dependency updates.

### 3.4 Verify PR Creation
After onboarding is merged, subsequent runs should open PRs for outdated dependencies. Check:
- Codeberg PRs tab
- Dependency Dashboard issue (created automatically if `dependencyDashboard: true`)

---

## Phase 4: Post-Deploy Tuning
**STATUS: PENDING**

### 4.1 Custom renovate.json in Repo
Add `renovate.json` to repo root for repo-specific overrides:

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

### 4.2 Enable SSH Commit Signing (optional)
If generated signing key, update CronWorkflow to mount the secret and set `RENOVATE_GIT_PRIVATE_KEY`.

### 4.3 Add GitHub Rate-Limit Token (optional)
For changelog/release note lookups without hitting GitHub rate limits:
- Generate GitHub PAT with `public_repo` scope
- Add to Vault/External Secret as `gh_token`
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
├── renovate-external-secret.yaml
├── renovate-pvc.yaml
├── renovate-configmap.yaml
└── renovate-cronworkflow.yaml
```

## Files to Update

- `docker/docs-site/docs/architecture/index.md` — Add Renovate to automation list
- `docker/docs-site/docs/index.md` — Mark renovate as complete in mid-term goals
- `docker/docs-site/docs/security/index.md` — Mark renovate as complete in future goals
- (Optional) Repo root `renovate.json` — after onboarding PR is created

---

## Execution Checklist

- [ ] Phase 0: Create Renovate bot account on Codeberg with full name + email
- [ ] Phase 0: Generate PAT with `repo`, `user`, `issue`, `organization` scopes
- [ ] Phase 0: Grant bot Write access to `bhamm-lab/bhamm-lab` repo
- [ ] Phase 0: (Optional) Generate SSH signing key and add public key to bot profile
- [ ] Phase 0: Add `renovate_token` (and optional `renovate_ssh_private_key`) to Vault
- [ ] Phase 1: Create `kubernetes/manifests/automations/renovate/` directory and manifests
- [ ] Phase 1: Verify ExternalSecret, PVC, ConfigMap, and CronWorkflow syntax
- [ ] Phase 2: Commit and push manifests
- [ ] Phase 2: Verify ArgoCD syncs new manifests to `argo` namespace
- [ ] Phase 3: Trigger manual run: `argo submit --from cronworkflow/renovate -n argo`
- [ ] Phase 3: Monitor workflow logs for errors
- [ ] Phase 3: Verify onboarding PR is created in Codeberg
- [ ] Phase 3: Merge onboarding PR
- [ ] Phase 3: Verify dependency update PRs are created on subsequent runs
- [ ] Phase 4: Tune `renovate.json` config in repo root
- [ ] Phase 5: Update docs-site with Renovate documentation
- [ ] Phase 5: Run `pre-commit` before final commit
