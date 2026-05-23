# Llama.cpp

For optimizing server args - https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

More docs - https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

## Distributed Inference via RPC

The two Strix Halo nodes are connected via USB4 point-to-point networking, enabling distributed inference for models that exceed a single node's ~128 GB unified memory.

### Architecture

- Each node runs an `rpc-server` DaemonSet on the USB4 interface (`10.30.0.78:50052` and `10.30.0.79:50052`)
- The `llama-server` frontend connects to both backends via `--rpc 10.30.0.78:50052,10.30.0.79:50052`
- Tensors are offloaded across both nodes' memory pools

### Deployment

**RPC Server DaemonSet** (runs on both nodes via `nodeSelector: machine_tier=accelerated`):

```yaml
command: ["rpc-server", "-H", "0.0.0.0", "-p", "50052"]
```

**Frontend model** (add to `helm-green.yaml`):

```yaml
args:
  - llama-server
  - -hf
  - unsloth/MiniMax-M2.5-GGUF:Q6_K_XL
  - --rpc
  - "10.30.0.78:50052,10.30.0.79:50052"
  - -ngl
  - "999"
```

### Limitations

| Issue | Detail |
|-------|--------|
| **No official image** | `ghcr.io/ggml-org/llama.cpp` images lack `rpc-server`. Custom build with `-DGGML_RPC=ON` required. |
| **PoC stability** | RPC can hang on large model tensor uploads. Test with `llama-bench` before `llama-server`. |
| **No RDMA** | Strix Halo USB4 does not support RDMA. Falls back to TCP over the 9 Gbps link. |
| **No bonding** | `thunderbolt_net` lacks MAC address setting; 802.3ad is broken. Use separate routes if multiple cables. |

### Benchmarking

```bash
llama-bench -m /models/... -ngl 99 --rpc 10.30.0.78:50052,10.30.0.79:50052
```
