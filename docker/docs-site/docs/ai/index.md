# AI Infrastructure

*Planning phase for homelab AI capabilities*

## Hardware Roadmap
- **Primary GPU**: AMD 7900 XTX
  - Hosting: Ollama/VLLM + OpenWebUI
- **Secondary GPU**: Intel Arc A310
  - Media: Encoding for Jellyfin
  - Light ML workloads for Immich
- **Compute Nodes**: Framework Motherboards (pre-ordered)
  - Distributed AI workloads

## Planned Stack
```mermaid
graph LR
A[7900XTX] --> B(Ollama/VLLM)
A --> C(OpenWebUI)
D[Arc A310] --> E(Immich/Jellyfin)
F[Framework] --> G[Distributed Nodes]
```

## Cloud Integration
- **Vertex AI API** for:
  - Overflow workloads
  - Specialized models
  - Temporary scaling

## Implementation Status
- 🚧 **Not started** - All plans conceptual
- PCIe passthrough configuration pending

**Next Steps**:
  - Setup Intel ARC A310 on Super node
  - Setup pcie passthrough and new talos VM with taint
  - Install Intel gpu k8s operator
  - Schedule immich and jellyfin to tainted Node
