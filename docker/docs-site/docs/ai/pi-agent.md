# Pi Coding Agent

[pi](https://pi.dev) (Mario Zechner's `@earendil-works/pi-coding-agent`) is installed inside the Hermes pod as a token-cheap coding worker. The Hermes `forge` profile orchestrates: forge plans and reviews (with project memory), pi executes edit/test loops against LiteLLM-served local models. Tickets: bhamm-lab Codeberg #346 (epic), #347 (this install).

- **Binary:** `/opt/data/tools/bin/pi` (npm global prefix on the `hermes-data` PVC — survives pod rebuilds, **not** in any image)
- **Wrapper:** `/opt/data/tools/pi-run`
- **Config:** `/opt/data/tools/pi/` (`models.json`, `settings.json`, `APPEND_SYSTEM.md`, `litellm-token`)
- **State:** per-profile under `~/.pi/agent` → e.g. forge sessions in `/opt/data/profiles/forge/home/.pi/agent/sessions/`
- **Model:** `qwen-38-27b` (r9700 vLLM via LiteLLM, `openai-completions`, Bearer auth)

## Design

Global binary + global config, **per-profile state**: `pi-run` symlinks `models.json`/`settings.json`/`APPEND_SYSTEM.md` into `$PI_CODING_AGENT_DIR` (default `$HOME/.pi/agent`, and each Hermes profile's shell `$HOME` is `/opt/data/profiles/<p>/home`), so model pins and pi's behavioral rules have one source of truth while sessions/auth stay scoped per profile. Access is policy-scoped: only profiles given the wrapper/skill use pi.

`APPEND_SYSTEM.md` is pi's user-level system-prompt append: the orchestrator's contract to the worker (commit on feature branches, **never push — no creds by design**, report "N commits ready for push", repo conventions). Rules live with the Hermes deployment, not the repo — the repo's `AGENTS.md` is cross-agent policy only. Delegation contract v3: pi commits in a token-less clone (push structurally impossible), Hermes reviews locally, re-prompts for fixes, and pushes only when review-clean.

`models.json` authenticates with `"apiKey": "$PI_LITELLM_TOKEN"` (env interpolation); the `pi-run` wrapper exports it by reading the token file at every launch — no shell command in the auth path. pi's `!command` resolvers were observed to fail nondeterministically in this container (error path swallows stderr; standalone repro always passed) so we avoid shell resolution entirely. Trade-off: a mid-session key rotation is picked up by new pi runs, not by a running one. The token (LiteLLM master key) is a 600 file on the PVC, same convention as the Hermes `TOKEN_FILE`.

Headless run:

```bash
/opt/data/tools/pi-run -d /path/to/repo -p 'implement TICKET.md'
```

## Reinstall / recovery

Run from inside the hermes pod (`kubectl exec` / dashboard terminal as the hermes user):

```bash
# 1. binary (pin the version you validated)
npm install -g --ignore-scripts --prefix /opt/data/tools @earendil-works/pi-coding-agent

# 2. config
mkdir -p /opt/data/tools/pi
cat > /opt/data/tools/pi/models.json <<'EOF'
{
  "providers": {
    "litellm": {
      "name": "bhamm-lab LiteLLM",
      "baseUrl": "http://litellm.litellm.svc.cluster.local:4000/v1",
      "api": "openai-completions",
      "apiKey": "$PI_LITELLM_TOKEN",
      "authHeader": true,
      "models": [
        {
          "id": "qwen-38-27b",
          "name": "Qwen 3.8 27B (r9700)",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 131072,
          "maxTokens": 16384,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
EOF
cat > /opt/data/tools/pi/settings.json <<'EOF'
{
  "defaultProvider": "litellm",
  "defaultModel": "qwen-38-27b",
  "defaultThinkingLevel": "medium",
  "quietStartup": true,
  "enableInstallTelemetry": false,
  "enableAnalytics": false,
  "defaultProjectTrust": "always",
  "compaction": { "enabled": true, "reserveTokens": 16384, "keepRecentTokens": 20000 },
  "retry": { "maxRetries": 5, "baseDelayMs": 2000, "maxAgentDelayMs": 15000,
             "provider": { "timeoutMs": 300000 } }
}
EOF

# 3. token — re-extract from the live gateway process env (no secrets in shell history):
python3 - <<'EOF'
import os, json
pid = json.load(open('/opt/data/gateway.pid'))['pid']
env = dict(p.split('=',1) for p in open(f'/proc/{pid}/environ','rb').read().decode().split('\0') if '=' in p)
open('/opt/data/tools/pi/litellm-token','w').write(env['OPENAI_API_KEY'].strip())
os.chmod('/opt/data/tools/pi/litellm-token', 0o600)
EOF

# 4. pi behavioral rules (orchestrator contract — see Design section)
cat > /opt/data/tools/pi/APPEND_SYSTEM.md <<'EOF'
# Hermes-pod pi — global rules (system prompt append)

You are the coding worker in a Hermes-orchestrated environment. The orchestrator (Hermes) plans tasks, reviews diffs, and owns everything that touches remotes.

When working in a git repository:
- Commit to your current feature branch as you work. Conventional Commits (`feat(scope): ...`, `fix(ai): ...`). One logical change per commit; if the work relates to a Codeberg issue, end the commit body with `Refs #<n>`. The body must describe the content actually in that commit — if you change your mind mid-commit (different replacement image, different URL), rewrite the message to match the final diff.
- NEVER run `git push` — clones here have no push credentials by design. When the task is complete, end your final message with `N commits on <branch> ready for push`.
- NEVER: commit or merge on `main`, force-push, rewrite already-pushed commits, delete branches, `git remote add`, or edit remote/credential config.
- When a task pins literals (download URLs, exact command forms, versions), transcribe them **verbatim** — do not "improve" the orchestrator's verified forms. Before committing a URL or rewritten command, prove it: HEAD-probe every download URL (expect 200); dry-run every rewritten command (`bash -n`, `--help`, or a no-op invocation).
- Never describe a container image or upstream as live/active/working based on search results alone. Prove resolution (`crane digest <ref>` or registry v2 API, rc=0) **and** identity (image OCI labels match the application). Pullable is not the same as correct.
- Verify before finishing: run whatever local validator proves the change (yaml parse, `shfmt -n`, `helm template`, tests) and report the exact commands + results in your final message.
- Calibration tasks (the ticket asks you to *measure*, not build): run the probes, change no code, and finish with a findings file (e.g. `CALIBRATION.md`) — one section per question, each answer carrying the exact command, exit code, and the decisive output line. The orchestrator decides from your findings; you do not choose the replacement.

House conventions (bhamm-lab work):
- Kubernetes manifests: 2-space indent, Google `yamlfmt` flow-map spacing (`{cpu: X}` not `{ cpu: X }`).
- Helm values changes: name the release + values file changed so the orchestrator can `helm template`.
- Infra changes: state which `docker/docs-site/docs/` page you checked for a needed update.
- Never touch files containing secrets (`*.enc.json`, `secrets.enc.yaml`); reference key names instead.
EOF

# 5. wrapper
cat > /opt/data/tools/pi-run <<'EOF'
#!/usr/bin/env bash
# pi-run — wrapper for the pi coding agent (hermes-data PVC, not in gitops).
set -euo pipefail
PI_HOME=/opt/data/tools/pi
BIN=/opt/data/tools/bin/pi
[ -x "$BIN" ] || { echo "pi-run: missing $BIN" >&2; exit 1; }
[ -f "$PI_HOME/litellm-token" ] || { echo "pi-run: missing litellm-token" >&2; exit 1; }
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
mkdir -p "$AGENT_DIR"
for f in models.json settings.json APPEND_SYSTEM.md; do
  tgt="$AGENT_DIR/$f"
  if [ ! -e "$tgt" ] && [ ! -L "$tgt" ]; then ln -s "$PI_HOME/$f" "$tgt"; fi
done
DIR="$PWD"
if [ "${1:-}" = "-d" ]; then DIR="$2"; shift 2; fi
export PI_LITELLM_TOKEN="$(cat "$PI_HOME/litellm-token")"
cd "$DIR"
exec "$BIN" "$@"
EOF
chmod +x /opt/data/tools/pi-run
```

Smoke test: `pi-run -p 'Reply with exactly: PI_OK'` in a scratch dir (first call may wait ~3 min for the vLLM pod to wake), then a tool-calling task (create + run a file).

## Notes

- `retry.provider.timeoutMs` is raised to 300s so vLLM cold-start wakes don't abort runs; kube-elasti keeps the model warm in practice.
- Tool-calling (read/write/edit/bash) works against raw LiteLLM with qwen-38-27b — verified; the gufo bridge is not needed for pi.
- Version as of install: pi **1.4.0**, installed 2026-10-25. Upgrade by re-running step 1 with an explicit version; record it here.
