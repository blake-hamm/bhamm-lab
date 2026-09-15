# vLLM Radiance (MXFP4) for AMD Radeon AI PRO R9700 (gfx1201)
#
# Base image ships ROCm + PyTorch + Triton + AITER + vLLM compiled for gfx1201.
# The radiance-vllm-mxfp4 repo's patch prelude, kernels, chat template and
# fp8_mtp.py are baked in at /patches (upstream mounts them at runtime instead).
#
# Build:
#   docker build -t harbor.bhamm-lab.com/library/vllm-radiance-mxfp4:latest docker/vllm-radiance-mxfp4

ARG RADIANCE_IMAGE=stilldeadcode/vllm-radiance:0.9.3
# radiance-vllm-mxfp4 v0.12.0
ARG RADIANCE_REPO_REF=5aeb71bc49904a2233c8ea056790ef8afe6b51cf

FROM ${RADIANCE_IMAGE}
ARG RADIANCE_REPO_REF

# git is required at runtime by the setup init container (libr4d clone + patch apply)
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN git clone -q https://codeberg.org/ggz14/radiance-vllm-mxfp4 /patches \
 && git -C /patches checkout -q "${RADIANCE_REPO_REF}"
