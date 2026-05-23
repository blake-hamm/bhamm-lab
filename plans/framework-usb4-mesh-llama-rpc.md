# Framework USB4 Mesh + llama.cpp RPC Plan

**Goal:** Connect two Framework Desktop nodes (`nose`, `tail`) via USB4 point-to-point networking and run distributed llama.cpp RPC inference for models >128 GB.

**Related Issue:** https://github.com/blake-hamm/bhamm-lab/issues/82

---

## Hardware

| Node | Hostname | IP (mgmt) | RAM | OS |
|------|----------|-----------|-----|----|
| nose | green-talos-worker-nose | 10.0.30.78 | 128 GB | Talos v1.11.3 |
| tail | green-talos-worker-tail | 10.0.30.79 | 128 GB | Talos v1.12.6 |

Both nodes have two rear USB4-C ports (40 Gbps capable). Front ports are USB 3.2×2 only and must not be used for this purpose.

---

## Current State (Phase 1 Complete)

- `nose` has been provisioned via `tofu apply` and joined the green cluster.
- **Version mismatch:** `nose` is on Talos `v1.11.3`; the rest of the cluster is `v1.12.6`.
- Thunderbolt controller is detected on both nodes (dmesg shows peer discovery).
- **Cable appears already connected:** `nose` dmesg shows `thunderbolt 0-2: Linux green-talos-worker-tail`.
- **`thunderbolt-net` module is NOT loaded** on either node; only `thunderbolt` core module is present.
- No `thunderbolt0`/`thunderbolt1` network interfaces exist yet.
- `nose` shows an AVC denial for `/usr/lib/udev/rules.d/99-thunderbolt.rules` (Talos 1.11.3).

---

## Phase 2 — Upgrade nose to v1.12.6

`nose` must match the cluster Talos version before applying thunderbolt networking patches.

```bash
export TALOSCONFIG=./tofu/proxmox/talos/result/talos-config-green.yaml

# Upgrade nose to v1.12.6 (uses the same factory schematic)
talosctl -n 10.0.30.78 upgrade --image factory.talos.dev/installer/<SCHEMATIC_ID>:v1.12.6

# Wait for reboot and confirm version
talosctl -n 10.0.30.78 version
talosctl -n 10.0.30.78 get members
```

**Success criteria:** `nose` reports `Talos (v1.12.6)` and Kubernetes node is Ready.

---

## Phase 3 — Load thunderbolt-net Kernel Module

The `siderolabs/thunderbolt` extension ships both `thunderbolt` and `thunderbolt-net`, but Talos does not auto-load `thunderbolt-net`. It must be declared in the machine config.

Apply this patch to **both** nodes:

```yaml
machine:
  kernel:
    modules:
      - name: thunderbolt
      - name: thunderbolt-net
```

Commands:

```bash
cat > /tmp/tb-modules.yaml <<'EOF'
machine:
  kernel:
    modules:
      - name: thunderbolt
      - name: thunderbolt-net
EOF

talosctl -n 10.0.30.78 patch --patch @/tmp/tb-modules.yaml
talosctl -n 10.0.30.79 patch --patch @/tmp/tb-modules.yaml
```

**Verify:**

```bash
talosctl -n 10.0.30.78 read /proc/modules | grep thunder
talosctl -n 10.0.30.79 read /proc/modules | grep thunder
```

Both should show `thunderbolt` and `thunderbolt-net` loaded.

---

## Phase 4 — Discover Bus Paths

With `thunderbolt-net` loaded and the cable connected, interfaces should appear. Identify which `busPath` on each node maps to the peer.

```bash
talosctl -n 10.0.30.78 get links | grep thunderbolt
talosctl -n 10.0.30.79 get links | grep thunderbolt
```

Then map peers via dmesg:

```bash
talosctl -n 10.0.30.78 dmesg | grep thunderbolt
talosctl -n 10.0.30.79 dmesg | grep thunderbolt
```

Look for lines like:

```
thunderbolt 0-2: Linux green-talos-worker-tail
```

Note the bus path (e.g., `0-1.0`, `0-2`, `1-1.0`). Talos may report it as `0-1.0` or similar in `get links -oyaml` under `busPath`.

**Success criteria:** Each node shows one `thunderbolt` link with `operationalState: up` and a known bus path.

---

## Phase 5 — Configure Point-to-Point IP Addresses

Using the discovered bus paths, apply per-node network patches.

**nose:**

```yaml
machine:
  network:
    interfaces:
      - deviceSelector:
          busPath: "0-2"          # <-- replace with discovered path
        dhcp: false
        mtu: 65520
        addresses:
          - 169.254.255.78/32
        routes:
          - network: 169.254.255.79/32
            metric: 2048
```

**tail:**

```yaml
machine:
  network:
    interfaces:
      - deviceSelector:
          busPath: "1-2"          # <-- replace with discovered path
        dhcp: false
        mtu: 65520
        addresses:
          - 169.254.255.79/32
        routes:
          - network: 169.254.255.78/32
            metric: 2048
```

Apply:

```bash
talosctl -n 10.0.30.78 patch --patch @/tmp/tb-nose.yaml
talosctl -n 10.0.30.79 patch --patch @/tmp/tb-tail.yaml
```

**Verify connectivity:**

```bash
talosctl -n 10.0.30.78 read /proc/net/arp | grep 169.254.255.79
```

Or run a privileged debug pod and `ping`.

---

## Phase 6 — Benchmark with iperf3

Run privileged debug pods on both nodes to test throughput.

**Server (nose):**

```bash
kubectl run iperf-nose --rm -i --restart=Never \
  --overrides='{"spec":{"hostNetwork":true,"nodeName":"green-talos-worker-nose","containers":[{"name":"iperf","image":"networkstatic/iperf3","command":["iperf3","-s","-B","169.254.255.78"]}]}}' \
  --image=networkstatic/iperf3
```

**Client (tail):**

```bash
kubectl run iperf-tail --rm -i --restart=Never \
  --overrides='{"spec":{"hostNetwork":true,"nodeName":"green-talos-worker-tail","containers":[{"name":"iperf","image":"networkstatic/iperf3","command":["iperf3","-c","169.254.255.78","-B","169.254.255.79","-t","30"]}]}}' \
  --image=networkstatic/iperf3
```

**Success criteria:** Sustained ~9–11 Gbps, zero retransmits, stable over 30 seconds.

> **Note:** Real-world USB4/Thunderbolt IP throughput is ~9–11 Gbps. The theoretical 40 Gbps is not achievable over this protocol stack. Parallel streams or bonding are not supported (`thunderbolt_net` lacks `ndo_set_mac_address`; 802.3ad bonding is broken).

---

## Phase 7 — Deploy llama.cpp RPC Servers

Build or use a pre-built image that includes `rpc-server` compiled with ROCm/Vulkan support.

**Option A (fastest):** Use Donato Capitella's pre-built image:

```yaml
image: kyuz0/amd-strix-halo-toolboxes:vulkan-radv
command: ["rpc-server", "-H", "0.0.0.0", "-p", "50052"]
```

**Option B (cleanest):** Build `ghcr.io/ggml-org/llama.cpp` with `-DGGML_RPC=ON` and your ROCm/Vulkan backend.

Deploy as a DaemonSet on both nodes, binding to the USB4 IP:

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

Add an RPC-capable model to the existing `helm-green.yaml` (or a new Argo Application). Example:

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
    - "169.254.255.78:50052,169.254.255.79:50052"
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
llama-bench -m /models/... -ngl 99 --rpc 169.254.255.78:50052,169.254.255.79:50052
```

**Success criteria:** Model loads across both nodes' memory pools and inference completes without hangs. Start with `llama-bench`; if stable, test `llama-server`.

> **Warning:** llama.cpp RPC is still PoC. Large model tensor uploads can crash or hang. Use `--tensor-split` if you need to control weight distribution.

---

## Known Limitations

| Limitation | Detail |
|------------|--------|
| **Throughput ceiling** | ~9–11 Gbps real-world over USB4/Thunderbolt IP. Not 40 Gbps. |
| **No RDMA** | Strix Halo USB4 does not support RDMA. RPC uses TCP. |
| **No bonding** | `thunderbolt_net` lacks MAC address setting; 802.3ad bonding is broken. |
| **Single link** | With two cables between two nodes, run two separate /32 routes with different metrics. Do not use LACP. |
| **RPC stability** | llama.cpp RPC can hang on very large models during tensor upload. Start with `llama-bench`. |
| **Talos 1.11.3 AVC** | The thunderbolt udev rules SELinux denial on 1.11.3 may have prevented interface creation. Upgrading to 1.12.6 is required. |

---

## Checkpoints

| Phase | Verify |
|-------|--------|
| 2 | `talosctl -n 10.0.30.78 version` shows `v1.12.6` |
| 3 | `/proc/modules` on both nodes contains `thunderbolt-net` |
| 4 | `talosctl get links` shows `thunderbolt0` (or similar) `up` |
| 5 | `ping` from `169.254.255.78` to `169.254.255.79` succeeds |
| 6 | `iperf3` shows ≥9 Gbps, zero packet loss |
| 7 | `rpc-server` listening on `:50052` on both nodes |
| 8 | `llama-bench` completes distributed inference |

---

## References

- GitHub Issue: https://github.com/blake-hamm/bhamm-lab/issues/82
- llama.cpp RPC docs: https://github.com/ggml-org/llama.cpp/blob/master/tools/rpc/README.md
- Talos Thunderbolt gists: https://gist.github.com/gavinmcfall/ea6cb1233d3a300e9f44caf65a32d519
- Jeff Geerling cluster: https://www.jeffgeerling.com/blog/2025/i-clustered-four-framework-mainboards-test-huge-llms/
- Donato Capitella 2-node setup: https://www.youtube.com/watch?v=0cIcth224hk
