---
title: "Kube-AI-Stack"
---

#### [kube-ai-stack](https://github.com/blake-hamm/kube-ai-stack)

This is a helm chart I created and maintain to enable an 'all-in-one' ai/ml platform on kubernetes. Inspired by the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), it includes subcharts for major LLMOps and MLOps frameworks like [MLflow](https://mlflow.org/) and [Arise Phoenix](https://phoenix.arize.com/). I began building this to fullfill a need in my homelab to run foundation models on limited hardware with [llama.cpp](https://github.com/ggml-org/llama.cpp) and provide an ai gateway with [LiteLLM](https://www.litellm.ai/). I have designed a unique way to scale models to zero using [Prometheus](https://prometheus.io/) and [KubeElasti](https://kubeelasti.dev/), allowing access to more models than hardware allows.
