# Forge: Sandboxed Hermes Agent on Talos

## Objective

Deploy [Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/docker) as a sandboxed, GitOps-managed workload in the Talos cluster. Primary persona: **tech lead for the homelab**. Expandable to more agents (fitness, executive assistant, planner) via Hermes profiles. Primary interface: **Telegram** (migrated from Signal). Secondary: Hermes Desktop over remote gateway.

> **MIGRATION (ADR): Signal → Telegram.** After the multi-agent rollout leaked replies into personal Signal groups (see "Signal incident" below), messaging was moved to Telegram. Telegram bots are **isolated accounts** — a bot can only see chats it is explicitly added to (DM to `@bot`, or a group you add the bot into). Unlike a Signal linked device, a Telegram bot has **no access to your personal chats**, so the entire class of "agent replied in a family/friends group" is eliminated by construction. One bot per profile; same multiplex/multi-profile model; first-class plugin platform (not a backported monkey-patch like the Signal authz). This ADR supersedes the Signal design that follows; the Signal content is retained for reference/rollback.

- **Name:** profile `forge` inside Hermes; infra (namespace, resources, OIDC client, secrets path) = `hermes`; hostname `hermes.bhamm-lab.com`
- **LLM backend:** LiteLLM (cluster-internal) via OpenAI-compatible env vars
- **Messaging:** Telegram via plugin platform (one bot per profile). ~~Signal via signal-cli sidecar~~ (retired)
- **Dashboard auth:** Hermes native self-hosted OIDC → Authelia (lldap backend). **No third-party auth.** No Authelia forward-auth middleware (breaks API/WebSocket clients; same pattern as harbor/vault).
- **Multi-agent:** one Deployment, one data PVC, many profiles (upstream-recommended)

## Architecture

```
Forge phone ➤ @forge_bot (Telegram, isolated bot account)
Mint phone  ➤ @mint_bot
Peak phone  ➤ @peak_bot
Default     ➤ @default_bot
                │  (bot only sees chats you add it to — no personal traffic)
Hermes Desktop ──TLS──> traefik-external ──> hermes pod :9119 (dashboard, OIDC-gated by Authelia)
                │
         hermes gateway run (s6-supervised)  ── multiplex ──> profiles forge/mint/peak/default
                │
        OPENAI_BASE_URL ──> litellm.litellm.svc :4000
                │
      /opt/data (cephfs RWX PVC, k8up backup) — all state, all profiles
```

> **Telegram is a plugin platform** (`/opt/hermes/plugins/platforms/telegram`), not a built-in adapter — enabled by a default-included plugin. Authorized via `TELEGRAM_BOT_TOKEN` (BotFather) plus `TELEGRAM_ALLOWED_USERS` / `TELEGRAM_GROUP_ALLOWED_CHATS`. Under `multiplex_profiles`, per-profile `.env` (secret scope) supplies each profile's own bot token via `agent.secret_scope.get_secret("TELEGRAM_BOT_TOKEN")` — one bot per agent. Uses long-polling (no inbound webhook/listener needed, so no extra ingress + no Cilium ingress rule; only outbound egress to Telegram).

Key facts driving design (from upstream docs):

- Image `nousresearch/hermes-agent` is s6-supervised, non-root, immutable `/opt/hermes`. All mutable state in `/opt/data`.
- **Never run two gateway containers against the same data dir.** One Deployment, `replicas: 1`, `strategy: Recreate`.
- Port 9119 = dashboard backend (Hermes Desktop remote gateway + web dashboard). Auth fails closed on non-loopback bind without a provider — we configure self-hosted OIDC.
- Port 8642 = OpenAI-compatible API server. Optional; enable with `API_SERVER_KEY` only if needed later.
- Desktop remote-gateway auth = session token or Nous Portal OAuth — **not** arbitrary OIDC. Desktop uses session token; browser uses Authelia OIDC.
- Unattended gateway needs `tool_loop_guardrails.hard_stop_enabled: true`.
- Resources: 2–4 Gi RAM / 2 CPU recommended (Playwright is the hog).

---

## Phase 0: Decisions

**STATUS: COMPLETE**

| Decision | Choice |
|---|---|
| Name | `forge` |
| Messaging | **Telegram** (one bot per profile: `forge_bot`, `mint_bot`, `peak_bot`, `default_bot`) — isolated bot accounts, no personal-chat exposure. ~~Signal~~ (retired) |
| Dashboard exposure | `hermes.bhamm-lab.com` via traefik-external, Hermes-native OIDC → Authelia |
| Desktop auth | Session token (stored in OS keychain by Desktop app) |
| Multi-agent | Profiles in one container, shared `/opt/data` cephfs PVC |
| Network policy | CiliumNetworkPolicy default-deny, explicit allowlist (first in cluster — template for others) |
| Secrets | `secrets.enc.json` → Vault sync workflow → ExternalSecret. No third-party IdP. |

Open (default proposed, confirm at implementation):

- **Telegram bot tokens:** create via `@BotFather` — one bot per agent profile. 4 bots: `forge_bot`, `mint_bot`, `peak_bot`, `default_bot`. Weigh using distinct bots (clean profile isolation, 4 tokens) vs one bot + command routing (1 token, needs chat/command routing). DECISION: distinct bot per profile — maps cleanly to per-profile secret scope, no routing ambiguity, and bot-level isolation prevents cross-profile leakage.

- **signal-cli sidecar image:** ~~(retired with Signal)~~ official `ghcr.io/asamk/signal-cli:0.14.7` JVM tag (pinned + digest) + `LANG=C.UTF-8`. RESOLVED: `linuxserver/signal` (GUI, no daemon API) and bbernhard REST wrapper (different API) incompatible with Hermes' native JSON-RPC+SSE daemon contract; `-client` tag = Rust JSON-RPC *client* tool, not the daemon. CHANGED during impl: `0.14.7-native` (GraalVM) dropped — native binary bakes an ASCII default charset at build time and ignores runtime `LANG` (signal-cli #2073), so `signal-cli link` QR codes render as `???` in terminals. JVM tag resolves UTF-8 from locale at runtime → QR renders correctly. Costs: ~+200–300 MiB RSS (fits the 1 Gi limit), larger image.

Resolved (changed from original assumption):

- **LiteLLM key:** reuse `LITELLM_MASTER_KEY` via ExternalSecret `remoteRef` to `/default/litellm` (open-webui pattern). LiteLLM free tier limits key count; master key acceptable for homelab.
- **Dashboard OIDC:** Hermes self-hosted OIDC provider is **public PKCE client only — no client_secret supported**. Authelia client `hermes` is `public: true` + S256. Callback path confirmed: `<public URL>/auth/callback` → `https://hermes.bhamm-lab.com/auth/callback`. Env: `HERMES_DASHBOARD_OIDC_ISSUER`, `HERMES_DASHBOARD_OIDC_CLIENT_ID`, `HERMES_DASHBOARD_PUBLIC_URL` (all non-secret → ConfigMap).

---

## Phase 1: Secrets

**Verify:** all keys visible in Vault at expected paths; `sops -d secrets.enc.json` clean.

1. ~~Create LiteLLM virtual key~~ → reuse master key via ExternalSecret (open-webui pattern), no sops entry needed.
2. `secrets.enc.json` `default.hermes` block: DONE — `API_SERVER_KEY` only (reserved for 8642 later). No OIDC secret (public PKCE client).
3. Authelia: `hermes` OIDC client added to `kubernetes/manifests/base/authelia/helm-all.yaml` — public client, PKCE S256, redirect `https://hermes.bhamm-lab.com/auth/callback`. DONE.
4. Run SOPS→Vault sync workflow (`kubernetes/manifests/automations/cicd/template-sops-vault-sync-all.yaml`). REMAINING.

---

## Signal incident (root cause + why we moved)

Multi-agent (multiplex) rollout leaked replies into personal Signal groups. Contributing causes (documented for the Telegram migration to avoid):

1. **Signal is a linked device on a personal number.** A linked Signal device can see/extract every message in every group the number belongs to. The `SIGNAL_GROUP_ALLOWED_USERS` allowlist only gates *responses*, not *visibility*. Any authz slip ⇒ reply in a personal group.
2. **Multiplex authz relied on a backported monkey-patch** (`authz-patch-configmap-green.yaml`, upstream PR #44706, unmerged). Under multiplex the group allowlist read fell through to process-global `os.getenv` when a profile had no `.env` — leaking profile A's allowlist across profiles (issue #72348 pattern).
3. **Concurrent gateways** ("Another Hermes process is using this session") during a SIGTERM respawn loop — multiple gateway processes independently processing inbound against one signal-cli daemon.

**Why Telegram fixes it:** Telegram bots are isolated accounts with no visibility outside chats they are added to; group authz is a first-class per-profile scoped gate in the plugin; each profile's bot token is isolated via per-profile secret scope. No monkey-patch, no shared personal account, no ambient traffic.

---

## Phase 2: Manifests — DONE

**Verify:** `argocd app diff` clean; pre-commit passes (yamlfmt, trivy).

Files written: `kubernetes/manifests/apps/ai/hermes/{namespace,common,deploy,service,networkpolicy}-green.yaml`. Discovery automatic via `green-apps` Application (`apps/**`, `{**all.yaml,**green.yaml}`) — no manual registration needed. Preview flow: `green-core` + `green-apps` + hermes' own Application pointed at `feature/hermes` branch (whole core+apps stacks track the branch while open; revert to `main` by editing `base/core-green.yaml` + `core/apps-green.yaml` once merged).

Deviations from original plan (verified against image Dockerfile + docker docs):

- PSA `privileged` namespace + no restrictive securityContext: container **starts as root** (s6-overlay PID 1); stage2-hook chowns `/opt/data`, services drop to `hermes` UID 10000 via `s6-setuidgid`. `runAsNonRoot`/drop-ALL would break stage2. Matches repo convention (amd, models, servarr all privileged).
- No `HERMES_PROFILE` env: profiles are first-class in-container (s6 slot per profile); `forge` profile created post-install. Dashboard on 9119 serves all profiles via switcher.
- Probes: tcpSocket on 9119 (no dashboard HTTP health endpoint).
- Image pinned to `nousresearch/hermes-agent:v2026.8.16.2@sha256:a39fc116...` (tag on 2026-08-17).
- ~~Signal sidecar added~~ (retired — see MIGRATION ADR). Replaced by Telegram plugin platform. No sidecar container needed; Telegram uses long-polling (outbound only). Deploy-green.yaml drops signal-cli container + `hermes-signal-cli` rbd PVC + `SIGNAL_*` env; adds `TELEGRAM_BOT_TOKEN` (per-profile secret scope) + `TELEGRAM_ALLOWED_USERS`/`TELEGRAM_GROUP_ALLOWED_CHATS`.
- Signal sidecar added: `ghcr.io/asamk/signal-cli:0.14.7@sha256:5b8059ae...` JVM tag + `LANG=C.UTF-8` + `PATH` prepending `/opt/signal-cli/bin` (JVM image binary lives there; GraalVM native build mangles terminal QR codes to `?` — see Phase 0), daemon runs single-account mode (`--account "$SIGNAL_ACCOUNT"` from Vault secret — multi-account mode fails to resolve the `account=` query param), PVC `hermes-signal-cli` → `/var/lib/signal-cli`, pod fsGroup 1000 (non-root `signal-cli` user), `SIGNAL_HTTP_URL=http://hermes:8080` (separate container netns — reached via the hermes Service, NOT loopback). Linking: built into the signal-cli container — self-linking bootstrap wrapper (deploy-green.yaml). If no account on PVC, it runs `signal-cli link -n $LINK_NAME` in the pod and logs the `tsdevice:` URI (non-TTY stdout suppresses the mangled terminal QR); QR-ify the URI locally (`qrencode -t ANSIUTF8 '<uri>'` or `-o qr.png`), scan on phone, then the same process execs the daemon. **Gotcha:** `--config=/var/lib/signal-cli` REPLACES the data root — account data lives at `/var/lib/signal-cli/data/accounts.json`, NOT `$HOME/.local/share/signal-cli/data` (that's the no-flag default). Mixing the two conventions was the real cause of the impl's `User +... is not registered` loops (exec-link wrote one path, daemon with `--config` read the other). No scaling, no extra pods: ArgoCD-safe. Verify via daemon logs — NOT via `signal-cli receive`/`listAccounts` while the daemon is up (use the daemon's JSON-RPC `listGroups` via curl instead — read-only, no concurrency). Channel config: `SIGNAL_ALLOWED_USERS=none` (DMs incl. Note-to-Self dropped as unauthorized), `SIGNAL_GROUP_ALLOWED_USERS` = the dedicated "hermes" group ID — group chat is the only live channel. Group-member authz requires upstream PR #44706 (open, unmerged at impl time); backported via `authz-patch-configmap-green.yaml` (ConfigMap subPath mount over `/opt/hermes/gateway/authz_mixin.py`, tied to image digest v2026.8.16.2 — regenerate on image bump, delete once the PR ships).
- `networkpolicy-green.yaml` DONE — first CiliumNetworkPolicy in repo. Default-deny + ingress (traefik→9119) + egress (DNS, litellm:4000, auth.bhamm-lab.com:443 for OIDC token exchange). Telegram migration: egress `api.telegram.org`/`core.telegram.org`:443 replaces the old `*.signal.org`/`*.whispersystems.org` rules (Telegram is outbound long-poll, no inbound listener). NOTE: egress deny blocks agent web tools (browser/curl/git) — append toFQDNs per profile as needed.

Deployment `hermes`, 1 replica, `strategy: Recreate`:

### `networkpolicy-green.yaml` — DONE (first CiliumNetworkPolicy in repo)

CiliumNetworkPolicies for namespace `hermes` (default-deny both directions):

- Ingress: traefik namespace pods → 9119
- Egress: kube-dns 53; litellm namespace 4000; `toFQDN` Signal servers 443 (signal-cli)
- Everything else denied. Future profiles needing e.g. GitHub get explicit FQDN rules appended.

---

## Phase 3: ArgoCD wiring & sync

**Verify:** app healthy, PVCs bound, ExternalSecret synced, pod running, networkpolicy active.

1. ~~Register `hermes` app~~ — not needed, `green-apps` Application auto-discovers `apps/**/*{all,green}.yaml`.
2. Sync; watch for: cephfs PVC bind, vault secret fetch, traefik route, Cilium enforcement (check `cilium monitor`/hubble for denied legit traffic).

---

## Phase 4: Bootstrap (manual, via `kubectl exec`) — Telegram

**Verify:** Telegram round-trip works per agent; Desktop connects; dashboard login via Authelia.

1. Create 4 bots in `@BotFather`: `/newbot forge_bot`, `mint_bot`, `peak_bot`, `default_bot`. Capture 4 bot tokens → per-profile secret scope (each profile's `.env` → `TELEGRAM_BOT_TOKEN=<token>`). Tokens live on PVC per profile, or in Vault for GitOps-mirrored profiles.
2. Find your Telegram user ID (pm `@userinfobot`) → set `TELEGRAM_ALLOWED_USERS` to your ID for every profile (tightest: only you can DM/trigger each bot).
3. Create a Telegram group per agent (`forge`, `mint`, `peak`, `default`) with ONLY you as member + the respective bot. Add bot → it sees only that group. `TELEGRAM_GROUP_ALLOWED_CHATS` = that group's chat id (or rely on group single-member isolation).
4. `kubectl exec -it deploy/hermes -c hermes -- hermes setup` (or write `config.yaml` directly on PVC): provider OpenAI-compatible, base URL litellm, key from env; `tool_loop_guardrails.hard_stop_enabled: true` with `exact_failure: 5`, `idempotent_no_progress: 5`.
5. Enable `gateway.multiplex_profiles: true` + explicit `gateway.profile_routes` mapping each Telegram chat → its profile (belt-and-suspenders with per-bot isolation; each bot's group only routes to that profile).
6. Test round-trip: message forge group → forge_bot replies only there; mint/peak/default isolated. Confirm no reply outside (bot cannot see other chats by construction).
7. SOUL.md per profile: distinct personas (forge=tech lead, mint=planning, peak=perf, etc.).
8. Dashboard OIDC: set issuer/client, confirm redirect URI, test browser login through Authelia.
9. Desktop: add Remote gateway connection `https://hermes.bhamm-lab.com`, session token auth, Test → "Reachable".

---

## Phase 4b: Retired Signal bootstrap (for rollback reference — DO NOT re-enable without revisiting authz)

1. Signal linking: `kubectl exec -it deploy/hermes -c signal-cli -- signal-cli link -n "forge"` → scan QR from phone (Settings → Linked Devices). Restart pod (daemon auto-starts via image CMD).
2. Signal config: `SIGNAL_ACCOUNT`, `SIGNAL_ALLOWED_USERS` (own number, E.164). Test Note-to-Self round trip.
3. Group authz requires the backported authz_mixin monkey-patch — see "Signal incident" above.

---

## Phase 5: Backup, docs, hardening follow-ups

**Verify:** k8up backup runs; docs site updated.

1. Confirm k8up picks up `hermes-data` (single state PVC — no more separate `hermes-signal-cli` PVC after migration; verify its removal).
2. Update `docker/docs-site/docs/` — new deployment doc for forge, **switched to Telegram** (follow existing deployment docs structure).
3. Follow-ups (not blocking):
   - Enable API server 8642 if Open WebUI/other tools should talk to forge
   - ServiceMonitor once metrics surface confirmed
   - Per-profile permission tuning (toolsets, terminal backend)
   - CiliumNetworkPolicy precedent → candidate task for forge itself: propose policies for other namespaces

---

## Risks / Notes

- **Single point of state:** one cephfs PVC for all profiles. Corruption hits every agent. Mitigation: k8up backups; consider per-profile rbd PVCs only if isolation becomes a requirement.
- **Telegram egress:** long-polling = outbound `api.telegram.org`/`core.telegram.org` only. Ensure CiliumNetworkPolicy allows it (no inbound ingress needed).
- **Telegram rate limits / flood control:** media/text batching built into adapter (`HERMES_TELEGRAM_MEDIA_BATCH_DELAY_SECONDS` etc.); aggressive agent reply bursts may hit flood-control — keep tool progress/notifications bottled up.
- **Webhook vs polling:** polling chosen (no inbound listener). If a webhook is ever preferred (needs ingress + `secret_token`), that is a later change — not default.
- **Bot token rotation:** if leaked, revoke in BotFather + rotate per-profile `.env`; no personal-account impact.
- **Hermes image upgrades:** pin tag, let Renovate propose updates (repo has renovate under automations).
- **Dashboard is the Desktop entrypoint** — if OIDC misconfigures, Desktop session token path must still work; test both after any auth change.

## References

- Hermes Docker guide: https://hermes-agent.nousresearch.com/docs/user-guide/docker
- Telegram integration: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram
- Desktop multi-connection: https://hermes-agent.nousresearch.com/docs/user-guide/multi-connection-desktop
- Cluster conventions: litellm (`apps/ai/litellm`), searxng deployment pattern, authelia OIDC clients (`base/authelia/helm-all.yaml`), vault secret flow (`automations/cicd`)
