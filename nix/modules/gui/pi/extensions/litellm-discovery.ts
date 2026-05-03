import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";

const BASE_URL = "https://litellm.bhamm-lab.com/v1";
const SECRET_PATH = "/run/secrets/litellm_api_key";

export default async function (pi: ExtensionAPI): Promise<void> {
  let apiKey: string;
  try {
    apiKey = readFileSync(SECRET_PATH, "utf-8").trim();
  } catch {
    console.warn("[litellm-discovery] secret not available, skipping");
    return;
  }

  try {
    const res = await fetch(`${BASE_URL}/models`, {
      headers: { Authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);

    const payload = await res.json() as { data: Array<{ id: string }> };

    pi.registerProvider("litellm", {
      baseUrl: BASE_URL,
      apiKey,
      authHeader: true,
      api: "openai-completions",
      compat: {
        supportsStore: false,
        supportsDeveloperRole: false,
        supportsReasoningEffort: false,
      },
      models: payload.data.map((m) => ({
        id: m.id,
        name: m.id,
        reasoning: false,
        input: ["text"] as const,
        contextWindow: 128000,
        maxTokens: 4096,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      })),
    });

    console.log(`[litellm-discovery] Registered ${payload.data.length} models`);
  } catch (e) {
    console.warn("[litellm-discovery] failed:", e);
  }
}
