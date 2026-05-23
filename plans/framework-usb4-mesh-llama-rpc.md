# Framework USB4 Mesh + llama.cpp RPC Plan

**Goal:** Connect two Framework Desktop nodes (`nose`, `tail`) via USB4 point-to-point networking and run distributed llama.cpp RPC inference for models >128 GB.

**Related Issue:** https://github.com/blake-hamm/bhamm-lab/issues/82

---

## Completed Setup (Phases 1–6)

| Item | Value |
|------|-------|
| **nose** (10.0.30.78) | Talos v1.12.6, `thunderbolt-net` loaded, `enx02438fee9b2c` @ `busPath: 0-2.0` |
| **tail** (10.0.30.79) | Talos v1.12.6, `thunderbolt-net` loaded, `enx020dce5a986d` @ `busPath: 1-2.0` |
| **iperf3** | 9.05 Gbits/sec sustained, 8 retransmits over 30 s |

---

## USB4 Mesh Network

| Node | Interface | busPath | IP |
|------|-----------|---------|-----|
| nose | `enx02438fee9b2c` | `0-2.0` | `10.30.0.78/32` |
| tail | `enx020dce5a986d` | `1-2.0` | `10.30.0.79/32` |

Dedicated `10.30.0.0/30` subnet. Point-to-point `/32` routes with metric 2048.

---

## Required Environment

```bash
export TALOSCONFIG=./tofu/proxmox/talos/result/talos-config-green.yaml
export KUBECONFIG=./tofu/proxmox/talos/result/kube-config-green.yaml
```

---

## IaC Changes Required

### 1. Talos Machine Config (`tofu/proxmox/talos/cluster.tf`)

Add to `talos_machine_configuration_apply.bare_metal.config_patches` for both nodes:

```yaml
machine:
  kernel:
    modules:
      - name: thunderbolt
      - name: thunderbolt-net
  network:
    interfaces:
      - deviceSelector:
          busPath: "0-2.0"   # nose
        dhcp: false
        mtu: 65520
        addresses:
          - 10.30.0.78/32
        routes:
          - network: 10.30.0.79/32
            metric: 2048
```

Tail uses `busPath: "1-2.0"`, address `10.30.0.79/32`, route `10.30.0.78/32`.

**Note:** Current nodes have stale duplicate addresses (`169.254.255.x` and `10.0.30.17x`). These must be cleaned up before or during the next `tofu apply`.

### 2. ArgoCD Namespace Metadata (`kubernetes/manifests/apps/ai/models/helm-green.yaml`)

The `models` namespace must enforce `privileged` pod security for host-network DaemonSets:

```yaml
spec:
  destination:
    namespace: models
  syncPolicy:
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: privileged
```

---

## Phase 7 — Deploy llama.cpp RPC Servers

**Problem:** Official `ghcr.io/ggml-org/llama.cpp` images do **not** include `rpc-server`. RPC requires a custom build with `-DGGML_RPC=ON`.

### Option A: Use Pre-Built Image (Fastest)

Donato Capitella's pre-built image includes `rpc-server` with Vulkan/RADV:

```yaml
image: kyuz0/amd-strix-halo-toolboxes:vulkan-radv
command: ["rpc-server", "-H", "0.0.0.0", "-p", "50052"]
```

### Option B: Build Custom Image (Recommended)

Build `ghcr.io/ggml-org/llama.cpp` with `-DGGML_RPC=ON` and your ROCm/Vulkan backend. Both `rpc-server` and `llama-server` must be built with RPC support.

### DaemonSet

Deploy on both nodes, binding to the USB4 IP:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: llama-rpc
  namespace: models
spec:
  selector:
    matchLabels:
      app: llama-rpc
  template:
    metadata:
      labels:
        app: llama-rpc
    spec:
      hostNetwork: true
      nodeSelector:
        machine_tier: accelerated
      tolerations:
        - key: "amd.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
      containers:
        - name: rpc
          image: kyuz0/amd-strix-halo-toolboxes:vulkan-radv
          command: ["/bin/sh", "-c"]
          args:
            - rpc-server -H 0.0.0.0 -p 50052
          env:
            - name: GGML_RPC_DEBUG
              value: "1"
          resources:
            limits:
              amd.com/gpu: 1
              memory: "120Gi"
            requests:
              amd.com/gpu: 1
              memory: "110Gi"
          volumeMounts:
            - name: models
              mountPath: /models
      volumes:
        - name: models
          hostPath:
            path: /var/lib/llama-cpp/models
            type: DirectoryOrCreate
```

**Verify:**

```bash
talosctl -n 10.0.30.78 read /proc/net/tcp | grep 50052
talosctl -n 10.0.30.79 read /proc/net/tcp | grep 50052
```

Both should show `rpc-server` listening on `0.0.0.0:50052`.

---

## Phase 8 — Run Distributed Inference

Add an RPC-capable model to `kubernetes/manifests/apps/ai/models/helm-green.yaml`:

```yaml
- name: distributed-large
  enabled: true
  image:
    repository: ghcr.io/ggml-org/llama.cpp
    tag: server-rocm-b8864   # must be built with GGML_RPC=ON
  args:
    - llama-server
    - -hf
    - unsloth/MiniMax-M2.5-GGUF:Q6_K_XL
    - --host
    - 0.0.0.0
    - --metrics
    - --no-webui
    - --jinja
    - -ngl
    - "999"
    - -fa
    - "on"
    - --rpc
    - "10.30.0.78:50052,10.30.0.79:50052"
    - -c
    - "65536"
  resources:
    limits:
      memory: "120Gi"
      cpu: "8"
    requests:
      memory: "110Gi"
      cpu: "4"
  nodeSelector:
    kubernetes.io/hostname: green-talos-worker-nose
```

**Benchmark:**

```bash
# Inside the client pod
llama-bench -m /models/... -ngl 99 --rpc 10.30.0.78:50052,10.30.0.79:50052
```

**Success criteria:** Model loads across both nodes' memory pools and inference completes without hangs. Start with `llama-bench`; if stable, test `llama-server`.

> **Warning:** llama.cpp RPC is still PoC. Large model tensor uploads can crash or hang. Use `--tensor-split` if you need to control weight distribution.

---

## Kubernetes Debug Notes

Host-network pods require a namespace with `pod-security.kubernetes.io/enforce=privileged`:

```bash
kubectl create ns debug-tb
kubectl label ns debug-tb pod-security.kubernetes.io/enforce=privileged --overwrite
```

Example ping test:

```bash
kubectl run ping-test -n debug-tb --rm -i --restart=Never \
  --overrides='{"spec":{"hostNetwork":true,"nodeName":"green-talos-worker-nose","containers":[{"name":"ping","image":"busybox","command":["ping","-c","3","10.30.0.79"]}]}}' \
  --image=busybox
```

---

## Known Limitations

| Limitation | Detail |
|------------|--------|
| **Throughput ceiling** | ~9–11 Gbps real-world over USB4/Thunderbolt IP. Not 40 Gbps. |
| **No RDMA** | Strix Halo USB4 does not support RDMA. RPC uses TCP. |
| **No bonding** | `thunderbolt_net` lacks MAC address setting; 802.3ad bonding is broken. |
| **Single link** | With two cables between two nodes, run two separate /32 routes with different metrics. Do not use LACP. |
| **RPC stability** | llama.cpp RPC can hang on very large models during tensor upload. Start with `llama-bench`. |
| **No official RPC image** | `ghcr.io/ggml-org/llama.cpp` images do not include `rpc-server`. Custom build required. |

---

## Checkpoints

| Phase | Verify |
|-------|--------|
| 2 | `talosctl -n 10.0.30.78 version` shows `v1.12.6` ✅ |
| 3 | `/proc/modules` on both nodes contains `thunderbolt-net` ✅ |
| 4 | `talosctl get links` shows `thunderbolt` interface `up` ✅ |
| 5 | `ping` across mesh succeeds ✅ |
| 6 | `iperf3` shows ≥9 Gbps, stable ✅ |
| 7 | `rpc-server` listening on `:50052` on both nodes |
| 8 | `llama-bench` completes distributed inference |

---

## References

- GitHub Issue: https://github.com/blake-hamm/bhamm-lab/issues/82
- llama.cpp RPC docs: https://github.com/ggml-org/llama.cpp/blob/master/tools/rpc/README.md
- Talos Thunderbolt gists: https://gist.github.com/gavinmcfall/ea6cb1233d3a300e9f44caf65a32d519
- Jeff Geerling cluster: https://www.jeffgeerling.com/blog/2025/i-clustered-four-framework-mainboards-test-huge-llms/
- Donato Capitella 2-node setup: https://www.youtube.com/watch?v=0cIcth224hk
