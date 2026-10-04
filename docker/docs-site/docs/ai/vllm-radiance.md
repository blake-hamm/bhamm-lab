# vLLM Radiance (MXFP4)

The `qwen-38-27b` deployment runs on the AMD R9700 node with [radiance-vllm-mxfp4](https://codeberg.org/ggz14/radiance-vllm-mxfp4) — a vLLM fork tuned for RDNA4 (gfx1201) with native MXFP4 kernels, R4D attention and a DFlash2 block-diffusion speculative drafter. This replaces the previous `llama.cpp` GGUF deployment for this model (roughly 2-4x decode throughput, much higher concurrency).

## Stack

- **Image:** `harbor.bhamm-lab.com/library/vllm-radiance-mxfp4` — derived image (`docker/vllm-radiance-mxfp4/Dockerfile`) based on `stilldeadcode/vllm-radiance` with the radiance repo baked in at `/patches` (upstream mounts it at runtime instead). The patch prelude, `radiance_mxfp4_fp8.so`, libr4d (`r4d.so`) and the AITER `module_aiter_core` JIT are compiled into site-packages at image build time (none need a GPU), so containers start straight into vLLM. Tag convention: `<radiance-base>-p<ggz14 prelude version>`, e.g. `0.9.3-p0.13.0`.
- **Checkpoint:** `amd/Qwen3.8-27B-Quark-AWQ-MXFP4`, requantized once by `fp8_mtp.py` (AMD's release does not load as-is) plus the `tcclaviger/Qwen3.8-27B-DFlash2-FP8` drafter. Both live on the model PVC (`/models/cache`).
- **libr4d:** pinned commit + `r4d_radiance_extras.patch`, built into the image at build time (the kernel shipped in the base image NaNs this model's gated-delta-net output).

## Deployment shape (kube-ai-stack)

The chart gained generic `command`, `env`, `initContainers`, `hostIPC` and `securityContext` passthroughs to support vLLM runtimes (it was llama.cpp-shaped before).

- **Setup init container:** downloads checkpoints, runs the fp8 MTP rewrite. All steps idempotent; cached on the PVC. (libr4d moved into the image build.)
- **Main container:** `exec /opt/radiance_entrypoint.sh` with `vllm serve` args (fp8 KV, TP=1, `--max-num-seqs 8`, dflash speculation). The patch/kernel prelude it used to run at every start is baked into the image now.
- **Compile caches** (`VLLM_CACHE_ROOT`, Triton, inductor, AITER) redirected onto the PVC — first start compiles for several minutes, restarts are fast.
- **Zeroscaling** trigger uses the `vllm:num_requests_running` Prometheus metric instead of the llama.cpp one.

## Expected performance (single R9700, reference numbers)

| Metric | Value |
|---|---|
| Decode, 1 stream | ~64 t/s |
| Decode, 8 concurrent (aggregate) | ~198 t/s |
| Prefill (0 ctx / 98k ctx) | ~2,600 / ~1,780 t/s |

## Operational notes

- **First sync is slow:** ~40 GiB of downloads plus a ~15 min checkpoint rewrite, then Triton/inductor warmup (kernel compilation itself now happens at image build). With everything cached, pod-ready coldstart is roughly 2.5-3 min.
- **Cache safety:** the compile cache dir is keyed to the image + config. If the engine dies at startup on an `N=0` GEMM after a config change, wipe `/models/cache/radiance/` on the PVC.
- **Context length:** `--max-model-len 114688`. The single R9700 with the vision tower resident leaves ~5.4 GiB for KV — vLLM rejects longer values (262144 needs 9.61 GiB). Dropping vision (`--language-model-only`) frees ~2 GiB and enables ~160k if you ever trade image input away.
- **Verify healthy startup** in the logs: `Using RadianceMxfp4W4A8LinearKernel`, `[radiance] native MXFP4 enabled on gfx12x`, and the R4D selections table.
