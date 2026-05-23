# Strix Halo

This is for my framework mainboard, also known as AMD Strix Halo (Ryzen AI Max+ 395) APU (particularly the gfx1151 RNDA 3.5 GPU).

## Resources
- https://strixhalo-homelab.d7.wtf/AI/AI-Capabilities-Overview
- https://github.com/lhl/strix-halo-testing/blob/main/README.md
- https://github.com/geerlingguy/ai-benchmarks/issues/21
- https://github.com/ROCm/ROCm/issues/5444
- https://github.com/kyuz0/amd-strix-halo-toolboxes

## USB4 Point-to-Point Networking

The two Strix Halo nodes are connected via rear USB4-C ports (40 Gbps) for distributed llama.cpp inference.

### Talos Configuration

The `siderolabs/thunderbolt` system extension is required in the schematic. The `thunderbolt-net` kernel module is loaded at runtime via machine config.

### Network Topology

| Node | Management IP | USB4 Interface | busPath | USB4 IP |
|------|---------------|----------------|---------|---------|
| nose | `10.0.30.78` | `enx02438fee9b2c` | `0-2.0` | `10.30.0.78/32` |
| tail | `10.0.30.79` | `enx020dce5a986d` | `1-2.0` | `10.30.0.79/32` |

Point-to-point `/32` routes with metric 2048:

- `nose` → route to `10.30.0.79/32` over `busPath: 0-2.0`
- `tail` → route to `10.30.0.78/32` over `busPath: 1-2.0`

### Performance

iperf3 benchmark (30 seconds):
- **Throughput:** ~9.05 Gbps sustained
- **Retransmits:** 8
- **MTU:** 65520 (jumbo frames)

### Infrastructure as Code

USB4 mesh config is declared in `tofu/proxmox/talos/green.tfvars` via `metal_amd_framework_workers`:

```hcl
metal_amd_framework_workers = {
  nose = {
    ip            = "10.0.30.78"
    usb4_bus_path = "0-2.0"
    usb4_mesh_ip  = "10.30.0.78"
    usb4_peer_ip  = "10.30.0.79"
    ...
  }
  tail = { ... }
}
```

The `talos_machine_configuration_apply.bare_metal` resource in `cluster.tf` renders the kernel modules and network interfaces from these values.
