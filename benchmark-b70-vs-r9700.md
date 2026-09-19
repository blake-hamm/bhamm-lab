# B70 vs r9700 — Qwen 3.8 27B serving benchmark

Issue: [#146](https://codeberg.org/blake-hamm/bhamm-lab/issues/146)

## Setup

| | r9700 | B70 |
|---|---|---|
| GPU | AMD Radeon Pro R9700 (32 GB) | Intel Arc Pro B70 (32 GB, Battlemage) |
| Stack | vLLM radiance (MXFP4 + DFlash spec decode) | Intel LLM-Scaler vLLM `0.14.0-b8.2.1` |
| Quant | **MXFP4** (pre-quantized, `amd/Qwen3.8-27B-Quark-AWQ-MXFP4`) | **INT4** (pre-quantized, `amd/Qwen3.8-27B-Quark-AWQ-INT4-W4A16`) |
| Node | `green-talos-worker-amd-r9700` | `green-talos-worker-intel-b70` |
| Served model | `qwen-38-27b` | `qwen-38-27b-b70` |

**Note:** the quantization differs per stack (MXFP4 vs INT4) because each
platform's native 4-bit format is used. The model (Qwen 3.8 27B), prompts,
batch size, and `max_tokens` are identical, so the token-generation throughput
is a fair comparison of the two serving stacks on the same model.

## How to run

```bash
python3 scripts/benchmark-b70-vs-r9700.py \
  --r9700 http://green-talos-worker-amd-r9700.bhamm-lab.com:8080 \
  --b70   http://green-talos-worker-intel-b70.bhamm-lab.com:8080 \
  --out   benchmark-results.json
```

Both endpoints must be serving. The script warms up (1 request per endpoint),
then runs a fixed 8-prompt set with `max_tokens=128`, `temperature=0`, and
reports per-request and aggregate (mean/median/min/max) tokens/s.

## Results

_Fill in after running the benchmark (Phase 3)._

| Metric | r9700 (MXFP4) | B70 (INT4) |
|---|---|---|
| Mean tok/s | _TBD_ | _TBD_ |
| Median tok/s | _TBD_ | _TBD_ |
| Min tok/s | _TBD_ | _TBD_ |
| Max tok/s | _TBD_ | _TBD_ |

### Per-request

_TBD — paste from `benchmark-results.json` `per_request` arrays._

## Observations

- **B70 first-boot watch:** Battlemage on AMD EPYC can brick at boot with
  `pcie_aspm.policy=powersupersave` (ASPM_L1.1). If the B70 node does not
  come up, check `journalctl` on the VM for PCIe errors and add a kernel arg
  override (`pcie_aspm=force`) to the schematic if needed.
- **INT4 quality:** if INT4 output quality is unacceptable, fall back to FP8
  (≈27 GB weights — tight on 32 GB, may need to lower `--max-model-len`).
- **VRAM headroom:** INT4 weights ≈14 GB, leaving ~18 GB for KV cache +
  runtime on the B70's 32 GB. The r9700 serves with ~28 GiB used.

## Reference

- Intel LLM-Scaler: https://github.com/intel/llm-scaler
- B70 vLLM image: `intel/llm-scaler-vllm:0.14.0-b8.2.1`
- INT4 checkpoint: `amd/Qwen3.8-27B-Quark-AWQ-INT4-W4A16`
- MXFP4 checkpoint: `amd/Qwen3.8-27B-Quark-AWQ-MXFP4`
