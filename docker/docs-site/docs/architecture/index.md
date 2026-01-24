# Overview

![bhamm-lab-diagram](../assets/diagram.png)


## Guiding Principles

This project is, first and foremost, a platform for learning and exploration. The core philosophy is to maintain a resilient and reproducible test environment where experimentation is encouraged. While this approach can sometimes lead to over-engineering (here's [the counter-argument](https://frenck.dev/the-enterprise-smart-home-syndrome/)), the primary goal is to guarantee that any component can be rebuilt from code.

This philosophy is supported by several key principles:

-   **Everything as Code:** All infrastructure, from bare-metal provisioning to application deployment, is defined declaratively and managed through version control. This ensures consistency and enables rapid disaster recovery.
-   **Monorepo Simplicity:** The entire homelab is managed within a single repository, providing a unified view of all services, configurations, and documentation.
-   **Open Source First:** I prioritize the use of open-source software to maintain flexibility and support the community.
-   **Accelerated AI/ML:** The environment is specifically tailored for AI/ML workloads, with a focus on leveraging AMD and Intel GPU acceleration for inference.

## Core Infrastructure

**Hardware:**

- **Servers:** 5 servers – 'Method' (SuperMicro H12SSL‑i), 'Indy' (SuperMicro D‑2146NT), 'Stale' (X10SDV‑4C‑TLN4F), 'Nose' & 'Tail' (Framework Mainboard)
- **Networking:** TP‑Link Omada switches & Protectli Opnsense firewall
- **Accelerated compute:** Intel Arc A310, AMD Radeon AI Pro R9700, AMD Ryzen AI MAX+ 395 (Strix Halo)
- **Management:** UPS, PiKVM

**Software Stack:**

- **Operating Systems**: [Debian](https://www.debian.org/), [Proxmox](https://www.proxmox.com/), [Talos](https://www.talos.dev/), [NixOS](https://nixos.org/), [Truenas](https://www.truenas.com/)
- **Storage:** [Ceph](https://ceph.io/) cluster (hot storage) and [Truenas](https://www.truenas.com/) (cold storage)
- **Container Orchestration:** Ephemeral [Talos](https://www.talos.dev/) [Kubernetes](https://kubernetes.io/) clusters and [Harbor](https://goharbor.io/) proxy/registry
- **Automation:** [OpenTofu](https://opentofu.org/), [Ansible](https://www.ansible.com/), [ArgoCD](https://argo-cd.readthedocs.io/en/stable/), [NixOS](https://nixos.org/), [Argo Events](https://argoproj.github.io/argo-events/) and [Argo Workflows](https://argoproj.github.io/argo-workflows/)
- **Security:** [SOPS](https://github.com/mozilla/sops), [HashiCorp Vault](https://www.vaultproject.io/), [Authelia](https://www.authelia.com/), [Traefik](https://traefik.io/traefik/), VLANs
- **Observability:** [Kube Prometheus Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), [Alloy](https://github.com/grafana/alloy), [LangSmith](https://www.langsmith.com/)

## Key Features

**AI/ML Capabilities:**

- 🤖 Managing device through [Intel GPU plugin](https://intel.github.io/intel-device-plugins-for-kubernetes/cmd/gpu_plugin/README.html) and [AMD ROCm operator](https://github.com/ROCm/gpu-operator)
- 🖼️ [Immich](https://immich.app/) machine learning & [Jellyfin](https://jellyfin.org/) transcoding with Intel Arc A310
- 📦 `llm-models` [Helm chart](kubernetes/charts/llm-models) – [KubeElasti](https://kubeelasti.dev/) scale‑to‑zero [Llama.cpp](https://github.com/ggml-org/llama.cpp) inference routed through [LiteLLM](https://github.com/BerriAI/litellm)
- 🧠 Embedding model inference with AMD Radeon AI Pro R9700
- ⚡ Dense & MoE inference on two AMD Ryzen AI MAX+ 395
- ☁️ GCP Vertex AI for larger ML inference

**Automation:**

- Infrastructure as Code with [OpenTofu](https://opentofu.org/)
- [Debian](https://www.debian.org/), [Proxmox](https://www.proxmox.com/) and [Opnsense](https://opnsense.org/) management with [Ansible](https://www.ansible.com/)
- GitOps deployment with [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
- Blue/green deployment strategies
- Container registry and proxy with [Harbor](https://goharbor.io/)
- [Argo Events](https://argoproj.github.io/argo-events/) and [Argo Workflows](https://argoproj.github.io/argo-workflows/) for backups, secret management and CI/CD pipelines
- [NixOS](https://nixos.org/) for Framework 13 laptop and Aorus gaming desktop
- [Common helm chart](kubernetes/charts/common)

**Storage & Backups:**

- [Ceph](https://ceph.io/) backbone
- [SeaweedFS](https://github.com/chrislusf/seaweedfs) PVC hot storage
- [Truenas](https://www.truenas.com/) / [MinIO](https://min.io/) cold storage
- Offsite replication to [Cloudflare R2](https://www.cloudflare.com/products/cloudflare-r2/)
- Automated backups with [Argo Workflows](https://argoproj.github.io/argo-workflows/), [k8up](https://github.com/k8up-io/k8up) and [CloudNative PG](https://cloudnative-pg.io/)

**Security:**

- Network segmentation with [OPNsense](https://opnsense.org/) and intervlan routing with TP Link Omada
- Secrets management with [SOPS](https://github.com/mozilla/sops) and [Vault](https://www.vaultproject.io/)
- Automated TLS certificates with [Cert Manager](https://cert-manager.io/) and [Cloudflare](https://www.cloudflare.com/)
- OIDC/MFA authentication with [Authelia](https://www.authelia.com/)
- Middleware and encrypted ingress with [Traefik](https://traefik.io/traefik)

**Disaster Recovery:**

- Infrastructure-as-Code for rapid rebuilding
- Automated backup restoration workflows and gitops
- Regular disaster recovery testing with blue/green cluster
- 3-2-1 backup strategy
