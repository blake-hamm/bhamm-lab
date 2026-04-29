# Plan: Custom Pi Extension for LiteLLM Dynamic Model Discovery

## Context

Pi's `pi-dynamic-models` extension (`@ssweens/pi-dynamic-models`) has a bug where it does not resolve `!command` syntax (e.g., `!cat /run/secrets/...`) before making its own HTTP requests. Pi's native `models.json` and `registerProvider()` handle this correctly, but the extension reads the raw string from its config file and sends it as the literal API key — causing HTTP 401 errors.

## Goals

1. Replace `pi-dynamic-models` with a minimal custom Pi extension
2. Resolve the sops-nix secret at extension runtime (not build time)
3. Fetch models from LiteLLM `/v1/models` with proper authentication
4. Register discovered models via `pi.registerProvider()`
5. Keep Nix config clean — no activation scripts, no plaintext secrets in store

## Approach

### Option A: Custom Extension (Recommended)

Write a single TypeScript extension file (`~/.pi/agent/extensions/litellm-discovery.ts`) that:
- Uses `execSync` to resolve the `!cat` command at extension load time
- Fetches `GET https://litellm.bhamm-lab.com/v1/models` with the resolved key
- Maps LiteLLM model list to Pi's `ProviderModelConfig` format
- Registers the provider via `pi.registerProvider()`

Pi's `registerProvider()` call will use the `!cat` syntax for the actual chat completions API — pi handles that natively. The resolved key is only needed for the discovery fetch.

### Option B: Make `/models` Public in LiteLLM

Configure LiteLLM proxy so `GET /v1/models` requires no auth. Then the extension fetches unauthenticated and only passes the auth key to `registerProvider()` for actual completions.

Requires LiteLLM config change. Simpler extension, but opens model enumeration.

### Option C: Fix `pi-dynamic-models` Upstream

PR to `@ssweens/pi-dynamic-models` to add `resolveValue()` matching Pi's `resolveConfigValue()`. Cleanest long-term, but blocked on upstream review/release.

## Recommended Implementation

Go with **Option A**. It's 20 lines of TypeScript, zero dependencies, fully self-contained.

## Implementation Steps

### 1. Remove `pi-dynamic-models`

In `nix/modules/gui/pi/default.nix`:
- Remove `"npm:@ssweens/pi-dynamic-models"` from `settings.json` packages
- Remove the `home.activation.piDynamicModels` script
- Remove `pi-dynamic-models.json` if it exists

### 2. Write the Extension

Create `nix/modules/gui/pi/extensions/litellm-discovery.ts`:

```typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { execSync } from "node:child_process";

const BASE_URL = "https://litellm.bhamm-lab.com/v1";
const SECRET_PATH = "/run/secrets/litellm_api_key"; // sops-nix mount point

function resolve(value: string): string {
  if (value.startsWith("!")) {
    return execSync(value.slice(1), { encoding: "utf-8", timeout: 5000 }).trim();
  }
  return process.env[value] ?? value;
}

export default async function (pi: ExtensionAPI): Promise<void> {
  const apiKey = resolve(`!cat ${SECRET_PATH}`);

  const res = await fetch(`${BASE_URL}/models`, {
    headers: { Authorization: `Bearer ${apiKey}` },
    signal: AbortSignal.timeout(8000),
  });

  if (!res.ok) {
    console.warn(`[litellm-discovery] Failed to fetch models: ${res.status} ${res.statusText}`);
    return;
  }

  const payload = await res.json() as { data: Array<{ id: string }> };
  const models = payload.data.map((m) => ({
    id: m.id,
    name: m.id,
    reasoning: false,
    input: ["text"] as ("text" | "image")[],
    contextWindow: 65536,
    maxTokens: 4096,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  }));

  pi.registerProvider("litellm", {
    baseUrl: BASE_URL,
    apiKey: `!cat ${SECRET_PATH}`,
    authHeader: true,
    api: "openai-completions",
    compat: {
      supportsStore: false,
      supportsDeveloperRole: false,
      supportsReasoningEffort: false,
    },
    models,
  });

  console.log(`[litellm-discovery] Registered ${models.length} models from LiteLLM`);
}
```

### 3. Wire into Nix Module

In `nix/modules/gui/pi/default.nix`, add:

```nix
home.file.".pi/agent/extensions/litellm-discovery.ts" = {
  force = true;
  source = ./extensions/litellm-discovery.ts;
};
```

### 4. Test

After NixOS rebuild / home-manager switch:
1. Verify `~/.pi/agent/extensions/litellm-discovery.ts` exists
2. Start `pi`
3. Check startup message: `[litellm-discovery] Registered N models from LiteLLM`
4. Press `Ctrl+L` or run `/model` — all LiteLLM models should appear

## Future Enhancements

- **Model metadata overrides**: Map known model IDs to better names, context windows, reasoning flags. Hardcode a small lookup table in the extension or read from a JSON config.
- **Multiple providers**: Generalize to support multiple LiteLLM instances or other OpenAI-compatible endpoints.
- **Caching**: Cache model list to a file to avoid re-fetching on every startup.
- **Contribute upstream**: Once the approach is validated, PR the `resolveValue` fix to `pi-dynamic-models` so the community benefits.

## Files to Modify

| File | Action |
|------|--------|
| `nix/modules/gui/pi/default.nix` | Remove `pi-dynamic-models` package, remove activation script, add extension file declaration |
| `nix/modules/gui/pi/extensions/litellm-discovery.ts` | Create (new file) |

## Risks

- **Secret path hardcoded**: If sops-nix secret path changes, extension breaks. Mitigation: keep path in sync with `sops.secrets.litellm_api_key.path` in the Nix module (currently `/run/secrets/litellm_api_key`).
- **LiteLLM unreachable**: Extension logs warning, pi starts without LiteLLM models. No crash.
- **TypeScript compilation**: Pi's extension loader should handle `.ts` files via its built-in transpilation. If not, compile to `.js` and ship the JS file instead.
