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

## IaC Changes

Applied via Talos machine config patches (`thunderbolt-net` module, USB4 interface `/32` routes) and ArgoCD `managedNamespaceMetadata` (`pod-security.kubernetes.io/enforce: privileged`). Both nodes have clean `10.30.0.x` addressing — stale `169.254.255.x` and `10.0.30.17x` duplicates removed.

---

## Phase 7 — Extend kube-ai-stack Chart

The `kube-ai-stack` Helm chart requires three generic toggles so that non-standard model workloads (like `rpc-server`) can reuse the same Deployment / ElastiService / PVC machinery without being forced into HTTP-oriented defaults. These are secondary/escape-hatch features — not first-class RPC support.

### Chart Changes (kube-ai-stack repo)

**`templates/deployment.yaml`** — add conditional blocks:

```yaml
    spec:
{{- if .hostNetwork }}
      hostNetwork: true
{{- end }}
      ...
{{- if (default true .probes.enabled) }}
          startupProbe:
            ...
          readinessProbe:
            ...
          livenessProbe:
            ...
{{- end }}
```

**`templates/servicemonitor.yaml`** — add conditional:

```yaml
{{- if and .enabled (default true .servicemonitor.enabled) }}
```

No RPC-specific templates, values keys, or documentation are added to the chart.

---

## Phase 8 — Deploy Distributed Model via helm-green.yaml

Add two model entries to `kubernetes/manifests/apps/ai/models/helm-green.yaml`.

### 8a — RPC Backend on `tail`

```yaml
- name: rpc-tail
  enabled: true
  description: RPC backend for distributed-large
  hostNetwork: true
  probes:
    enabled: false
  servicemonitor:
    enabled: false
  args:
    - rpc-server
    - -H
    - 0.0.0.0
    - -p
    - "50052"
    - -c
  resources:
    limits:
      amd.com/gpu: 1
      memory: "124Gi"
    requests:
      amd.com/gpu: 1
      memory: "110Gi"
  nodeSelector:
    kubernetes.io/hostname: green-talos-worker-tail
  zeroscaling:
    enabled: true
    minReplicas: 0
    cooldownPeriod: 1200
    trigger:
      query: >-
        sum(kube_deployment_status_replicas{deployment="distributed-large",namespace="models"}) or vector(0)
      threshold: "1"
```

**Why `hostNetwork: true`:** The `rpc-server` must bind to the USB4 interface (`10.30.0.79`). Pod network is not routable from `nose`'s USB4 link.

**Why `probes.enabled: false`:** `rpc-server` has no HTTP endpoint.

**Why `servicemonitor.enabled: false`:** Prevents Prometheus scrape noise on a non-HTTP workload.

**Scale trigger:** Watches `kube_deployment_status_replicas` for the main model. Fires immediately when the main model scales up, before `llama-server` starts. Avoids deadlock.

### 8b — Distributed Model on `nose`

```yaml
- name: distributed-large
  enabled: true
  description: Distributed inference across nose+tail
  pvc:
    storage: "100Gi"
  image:
    tag: vulkan-radv
  args:
    - /bin/bash
    - -c
    - |
      until bash -c 'echo >/dev/tcp/10.30.0.79/50052' 2>/dev/null; do sleep 5; done
      exec llama-server \
        -hf unsloth/MiniMax-M2.5-GGUF:Q6_K_XL \
        --host 0.0.0.0 \
        --metrics \
        --no-webui \
        --jinja \
        --no-mmap \
        -fa on \
        -ngl 999 \
        -dio \
        --rpc 10.30.0.79:50052 \
        -c 65536 \
        --timeout 1800 \
        -v
  resources:
    limits:
      amd.com/gpu: 1
      memory: "124Gi"
      cpu: "8"
    requests:
      amd.com/gpu: 1
      cpu: "4"
      memory: "110Gi"
  nodeSelector:
    kubernetes.io/hostname: green-talos-worker-nose
  zeroscaling:
    enabled: true
    minReplicas: 0
    cooldownPeriod: 1800
    trigger:
      query: >-
        sum(llamacpp:requests_processing{container="distributed-large"}) or vector(0)
      threshold: "1"
```

**Notes:**
- `--rpc` points **only** to `tail` (remote). `nose`'s GPU is used locally; listing `nose`'s own IP would double-count it.
- `-dio` (direct I/O) is required for large models on Strix Halo UMA. Without it, `llama-server` hangs indefinitely at `load_tensors` during RPC tensor upload. Donato's `models.ini.example` sets `direct-io = on` globally for the same reason.
- The bash `/dev/tcp` wait loop blocks startup until the RPC server is reachable. No extra binaries needed.

---

## Verification

**Check both scale to 0 when idle:**

```bash
kubectl get deploy -n models rpc-tail distributed-large
# Expect 0/0 replicas after cooldown period with no traffic
```

**Check RPC server listening on `tail`:**

```bash
talosctl -n 10.0.30.79 read /proc/net/tcp | grep 50052
```

**Benchmark:**

```bash
kubectl exec -n models deploy/distributed-large -- \
  llama-bench -m /models/cache/... -ngl 99 --rpc 10.30.0.79:50052
```

**Success criteria:** Model loads across both nodes' memory pools and inference completes without hangs.

---

## Known Limitations

| Limitation | Detail |
|------------|--------|
| **Throughput ceiling** | ~9–11 Gbps real-world over USB4/Thunderbolt IP. Not 40 Gbps. |
| **No RDMA** | Strix Halo USB4 does not support RDMA. RPC uses TCP. |
| **No bonding** | `thunderbolt_net` lacks MAC address setting; 802.3ad bonding is broken. |
| **Single link** | With two cables between two nodes, run two separate /32 routes with different metrics. Do not use LACP. |
| **RPC stability** | llama.cpp RPC is PoC. Start with `llama-bench`; if stable, test `llama-server`. |
| **kube-state-metrics dependency** | RPC server scale-up relies on `kube_deployment_status_replicas` being scraped by Prometheus. |
| **Strix Halo UMA** | Large models require `-dio` to avoid mmap↔HIP collision during tensor upload. |

---

## Checkpoints

| Phase | Verify |
|-------|--------|
| 2 | `talosctl -n 10.0.30.78 version` shows `v1.12.6` ✅ |
| 3 | `/proc/modules` on both nodes contains `thunderbolt-net` ✅ |
| 4 | `talosctl get links` shows `thunderbolt` interface `up` ✅ |
| 5 | `ping` across mesh succeeds ✅ |
| 6 | `iperf3` shows ≥9 Gbps, stable ✅ |
| 7 | Chart PR merged with generic toggles |
| 8 | `distributed-large` scales from 0, loads model across both nodes, inference completes |

---

## References

- GitHub Issue: https://github.com/blake-hamm/bhamm-lab/issues/82
- llama.cpp RPC docs: https://github.com/ggml-org/llama.cpp/blob/master/tools/rpc/README.md
- llama.cpp RPC UMA hang fix (`-dio`): https://github.com/ggml-org/llama.cpp/issues/19745
- Strix Halo toolboxes: https://github.com/kyuz0/amd-strix-halo-toolboxes
- Talos Thunderbolt gists: https://gist.github.com/gavinmcfall/ea6cb1233d3a300e9f44caf65a32d519
- Jeff Geerling cluster: https://www.jeffgeerling.com/blog/2025/i-clustered-four-framework-mainboards-test-huge-llms/
- Donato Capitella 2-node setup: https://www.youtube.com/watch?v=0cIcth224hk
