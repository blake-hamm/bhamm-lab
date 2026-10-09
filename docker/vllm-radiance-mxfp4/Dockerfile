# vLLM Radiance (MXFP4) for AMD Radeon AI PRO R9700 (gfx1201)
#
# Base image ships ROCm + PyTorch + Triton + AITER + vLLM compiled for gfx1201.
# The radiance-vllm-mxfp4 repo's patch prelude, kernels, chat template and
# fp8_mtp.py are baked in at /patches (upstream mounts them at runtime instead).
#
# The patch prelude, the MXFP4 GEMM kernel, the libr4d extras build and the
# AITER core-JIT are ALSO applied into site-packages at build time (RUN steps
# below). Everything the containers used to mutate/compile at every pod start
# is baked here -- that churn was most of the model coldstart. None of it needs
# a GPU: the patch scripts only rewrite source files (they read no env at
# patch time; every RADIANCE_* gate is runtime), and hipcc compiles without a
# device -- the community image builds its own kernels the same way.
#
# Built by CI (automations/cicd/forgejo-docker-all.yaml: kaniko, any push
# touching docker/) which publishes ONLY :latest to Harbor -- the version
# pins live in the ARGs below, not in image tags, until the pipeline grows
# per-build tagging. Manual build:
#   docker build -t harbor.bhamm-lab.com/library/vllm-radiance-mxfp4:latest docker/vllm-radiance-mxfp4
# (trigger bump for the docker-change workflow)

ARG RADIANCE_IMAGE=stilldeadcode/vllm-radiance:0.9.3
# radiance-vllm-mxfp4 v0.13.0
ARG RADIANCE_REPO_REF=938c4d25dd9635e668ee12c94cef99eb33ff4666
# libr4d pin the prelude expects (GDN overflow fix); build.sh defaults to gfx1201
ARG R4D_REPO_REF=b9e42ab

FROM ${RADIANCE_IMAGE}
ARG RADIANCE_REPO_REF
ARG R4D_REPO_REF

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Patch prelude at /patches: still needed at runtime by the setup init
# container (fp8_mtp.py) and by serve args (chat template). Fetched by SHA --
# no git credentials at build, byte-reproducible.
RUN curl -fsSL "https://codeberg.org/ggz14/radiance-vllm-mxfp4/archive/${RADIANCE_REPO_REF}.tar.gz" | tar xz -C /tmp \
 && mv /tmp/radiance-vllm-mxfp4 /patches

# Bake the 19-patch prelude + helper modules + tuned aiter GEMM configs + the
# MXFP4 fp8-WMMA kernel into site-packages (the patch scripts are idempotent
# and rerun-safe). This is what the main container ran at every pod start;
# hipcc runs under a login shell so ROCm lands on PATH exactly as it did then.
RUN bash -lc '\
 set -e; \
 SP=/opt/vllm/lib/python3.12/site-packages; \
 cd /patches; \
 for p in patch_quark_mxfp4 patch_tp3_pad patch_ar_maxbytes patch_topk_triton_rows \
     patch_dflash_calib patch_dflash_mxfp4_kv patch_rmsquant_fusion patch_verify_head \
     patch_kv_group_size patch_topk_composite patch_gdn_shared_build patch_dflash_selector_topk \
     patch_gdn_merge_inproj patch_dynwidth patch_async_dynwidth patch_step_trace \
     patch_ar_geometry patch_ar_3rank patch_gdn_glue; do \
   python3 "$p.py"; \
 done; \
 python3 patch_qwen3_thinkoff.py \
   || echo "[build] WARNING: thinkoff patch did not apply; thinking-off requests will return empty content"; \
 cp mxfp4-configs/*.json "$SP"/aiter/ops/triton/configs/gemm/; \
 cp radiance_mxfp4.py radiance_gdn.py radiance_rmsquant.py radiance_drafthead.py \
    radiance_verifyhead.py radiance_gdnmerge.py radiance_aroverlap.py radiance_topk.py \
    radiance_arnq.py radiance_tp3pad.py "$SP"/; \
 hipcc -O3 -w -std=c++17 -fPIC -shared --offload-arch=gfx1201 \
   $(python3 -m pybind11 --includes) radiance_mxfp4_fp8.hip -o "$SP"/radiance_mxfp4_fp8.so; \
 python3 -c "import radiance_mxfp4_fp8" && echo "[build] radiance_mxfp4_fp8.so OK"'

# libr4d pinned kernels + radiance extras (previously built by the setup init
# container onto the model PVC, then cp'd into site-packages at every start).
RUN bash -lc '\
 set -e; \
 curl -fsSL "https://codeberg.org/StillDeadcode/libr4d/archive/${R4D_REPO_REF}.tar.gz" | tar xz -C /tmp; \
 cd /tmp/libr4d; \
 git apply /patches/r4d_radiance_extras.patch; \
 ./build.sh; \
 cp r4d.so /opt/vllm/lib/python3.12/site-packages/r4d.so; \
 rm -rf /tmp/libr4d; \
 cd /; \
 python3 -c "import r4d" && echo "[build] libr4d ${R4D_REPO_REF} (rx) -> site-packages OK"'

# Pre-build AITER's module_aiter_core (~36 s of hipcc JIT every pod start).
# GPU_ARCHS removes GPU detection from the path so this also works on
# GPU-less build hosts; the running arch is always gfx1201, so the .so is
# valid wherever the image runs. Best-effort: on failure the runtime JIT
# rebuilds at startup as before (aiter re-checks the .so offload archs).
RUN bash -lc '\
 cd /opt/vllm/lib/python3.12/site-packages/aiter; \
 GPU_ARCHS=gfx1201 python3 -c "from aiter.jit.core import get_module; get_module(\"module_aiter_core\")" \
   && echo "[build] aiter module_aiter_core prebuilt OK" \
   || echo "[build] WARNING: aiter JIT prebake failed; startup will JIT module_aiter_core (~36 s)"'
