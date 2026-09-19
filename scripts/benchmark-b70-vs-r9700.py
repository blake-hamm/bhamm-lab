#!/usr/bin/env python3
"""
B70 vs r9700 serving benchmark (issue #146).

Serves the SAME model (Qwen 3.8 27B) on two different stacks and measures
token-generation throughput with identical prompts and batch sizes:
  - r9700 : MXFP4 (radiance), endpoint  green-talos-worker-amd-r9700
  - B70   : INT4  (LLM-Scaler vLLM), endpoint green-talos-worker-intel-b70

The quantization differs per stack (MXFP4 vs INT4) — this is expected and is
noted in the results. Everything else (prompts, batch size, max_tokens) is
held identical so the tokens/s comparison is apples-to-apples on the model.

Usage:
  python3 scripts/benchmark-b70-vs-r9700.py \
      --r9700 http://<r9700-host>:8080 \
      --b70   http://<b70-host>:8080 \
      --out   benchmark-results.json

If only one endpoint is reachable (e.g. B70 not yet online), pass the other
and omit the unreachable one — the script reports whichever is available.
"""
import argparse
import json
import statistics
import time
import urllib.request
import urllib.error

# Fixed prompt set (identical for both stacks). Mix of short/medium lengths.
PROMPTS = [
    "Explain how a B+ tree indexes work, with a concrete example.",
    "Write a Python function that computes the longest common subsequence of two strings, and explain its time complexity.",
    "Summarize the key differences between TCP and UDP in a table.",
    "Describe the trade-offs of using a content-addressed store for CI artifacts.",
    "Write a short poem (8 lines) about a homelab at 3am during a deploy.",
    "Explain what a KV cache is in a transformer inference engine and why it matters for latency.",
    "Draft a runbook for rotating a TLS certificate on a Traefik ingress.",
    "Explain PCIe ASPM power states and why L1.1 can cause boot issues on AMD platforms.",
]
MAX_TOKENS = 128
WARMUP = 1


def chat(base_url: str, prompt: str, model: str, max_tokens: int):
    """One chat completion; returns (n_tokens, latency_s)."""
    url = f"{base_url}/v1/chat/completions"
    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
        "stream": False,
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.load(resp)
    latency = time.perf_counter() - t0
    n_tokens = data.get("usage", {}).get("completion_tokens")
    if n_tokens is None:
        # Fallback: estimate from text length (~4 chars/token)
        text = data["choices"][0]["message"]["content"]
        n_tokens = max(1, len(text) // 4)
    return n_tokens, latency


def probe(base_url: str):
    """Check the endpoint is up and return the served model name."""
    try:
        with urllib.request.urlopen(f"{base_url}/v1/models", timeout=10) as resp:
            data = json.load(resp)
        models = [m.get("id") for m in data.get("data", [])]
        return models[0] if models else "unknown"
    except Exception as e:
        return None


def bench(base_url: str, label: str, model: str):
    print(f"\n=== {label} ({base_url}) model={model} ===")
    # Warmup (JIT / graph capture / KV cache)
    for i in range(WARMUP):
        chat(base_url, PROMPTS[i % len(PROMPTS)], model, MAX_TOKENS)
    print(f"warmup done ({WARMUP} requests)")

    results = []
    for i, prompt in enumerate(PROMPTS):
        n_tokens, latency = chat(base_url, prompt, model, MAX_TOKENS)
        tps = n_tokens / latency
        print(f"  [{i+1}/{len(PROMPTS)}] {n_tokens:4d} tok in {latency:6.2f}s -> {tps:6.1f} tok/s")
        results.append({"prompt_idx": i, "tokens": n_tokens, "latency_s": round(latency, 3), "tok_per_s": round(tps, 2)})

    tps_vals = [r["tok_per_s"] for r in results]
    return {
        "label": label,
        "model": model,
        "max_tokens": MAX_TOKENS,
        "per_request": results,
        "mean_tok_per_s": round(statistics.mean(tps_vals), 2),
        "median_tok_per_s": round(statistics.median(tps_vals), 2),
        "min_tok_per_s": round(min(tps_vals), 2),
        "max_tok_per_s": round(max(tps_vals), 2),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--r9700", default=None, help="r9700 vLLM base URL (MXFP4)")
    ap.add_argument("--b70", default=None, help="B70 vLLM base URL (INT4)")
    ap.add_argument("--out", default="benchmark-results.json")
    args = ap.parse_args()

    report = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "note": "Same model (Qwen 3.8 27B), different quant per stack: r9700=MXFP4 (radiance), B70=INT4 (LLM-Scaler vLLM). Same prompts and batch size.",
        "prompts": PROMPTS,
        "results": {},
    }

    for url, label, quant in [
        (args.r9700, "r9700-mxfp4", "MXFP4"),
        (args.b70, "b70-int4", "INT4"),
    ]:
        if not url:
            continue
        model = probe(url)
        if not model:
            print(f"[{label}] endpoint {url} not reachable — skipping")
            report["results"][label] = {"error": "endpoint not reachable"}
            continue
        report["results"][label] = bench(url, f"{label} ({quant})", model)

    with open(args.out, "w") as f:
        json.dump(report, f, indent=2)

    print(f"\n=== SUMMARY (written to {args.out}) ===")
    for label, r in report["results"].items():
        if "error" in r:
            print(f"  {label}: {r['error']}")
        else:
            print(f"  {label}: mean {r['mean_tok_per_s']} tok/s | median {r['median_tok_per_s']} | min {r['min_tok_per_s']} | max {r['max_tok_per_s']}")


if __name__ == "__main__":
    main()
