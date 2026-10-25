# Vendored verbatim from ggz14/radiance-vllm-mxfp4 @ 45da506 (main, 2026-09-26;
# the script landed post-v0.13.0 upstream). Kept byte-identical to upstream for a
# clean re-diff on future prelude bumps -- provenance lives here, not in the
# script. Do not edit; re-vendor from upstream main instead.
#
#!/usr/bin/env python3
# bake_aiter_core.py -- pre-bake aiter's `module_aiter_core` JIT .so at image build time,
# called from the Dockerfile recipes (COPY + RUN python3 this file).
#
# Why: aiter builds this .so lazily on first use (once per ~30 min on every cold container
# spot), and the recipe's env is not --rm between builds -- both facts keep the per-boot
# rebuild alive. This drives the exact same build at image-build time (hipcc needs no GPU;
# the runtime then adopts the .so: arch markers match the device, no rebuild) and the three
# other build-failure modes (missing-ape pull, version-skip, python-traceback) are all
# zero-exit-code -> the bake is simply re-attempted at runtime.
# Fidelity: aiter's own core.build_module("module_aiter_core") with the per-module arguments
# of get_args_of_build (optCompilerConfig.json: single TU aiter_core_pybind.cu, -DENABLE_CK=0,
# torch-excluded); env diffs only GPU_ARCHS / CU_NUM (set per-process, not image ENV).
#
# Repository file, called in-place by the recipe: the classic builder (DOCKER_BUILDKIT=0,
# RUN on python - is not discarded and exits cleanly); the file form is 100% safe under
# both classic and buildkit. The assertions / exceptions below determine the result of the step
# -- a loud failure, not a silently skipped bake.
import importlib.util, os, shutil, sys, sysconfig

import importlib.util, os, shutil, sys, sysconfig

sp = sysconfig.get_paths()["purelib"]
jit = os.path.join(sp, "aiter", "jit")
assert os.path.isfile(os.path.join(jit, "core.py")), \
    f"no aiter JIT tree at {jit} -- base layout changed; re-audit this block"
assert os.path.isfile(os.path.join(jit, "optCompilerConfig.json")), \
    f"no aiter optCompilerConfig.json in {jit} -- base layout changed"

# Build-env deltas (process scope only, so the served env stays byte-identical
# to the launcher's; aiter reads them for the build flags the runtime would
# otherwise resolve from a live device query):
os.environ["GPU_ARCHS"] = "gfx1201"   # this image's arch (the live-resolved value)
os.environ["CU_NUM"] = "64"          # R9700 CU count (escha/RESULTS_tuning.md: "64-CU part")
# MAX_JOBS intentionally left unset: aiter's check_and_set_ninja_worker caps
# jobs by cores (0.8x) and free memory (0.5 GB/job) on its own.

# aiter's jit/core.py resolves chip_info / cpp_extension / file_baton /
# torch_guard as bare module names (all in jit/utils/), but the wheel's top
# package never puts utils/ on sys.path (its __init__.py is the license header
# only). Load core.py standalone with the utils dir on the path -- the same
# package-relative resolution aiter's JIT invocation itself yields.
sys.path.insert(0, os.path.join(jit, "utils"))
spec = importlib.util.spec_from_file_location("_aiter_jit_core", os.path.join(jit, "core.py"))
core = importlib.util.module_from_spec(spec)
sys.modules["_aiter_jit_core"] = core
spec.loader.exec_module(core)

# Drive the exact build the runtime's first use triggers: its ops call
# core.build_module(md) with get_args_of_build(md) -- the same optCompilerConfig
# entry and args. The config-identity assert bakes loud on any drift and the
# --offload-arch flag below comes from the env above, so a future aiter source
# change (new base) rebuilds a byte-identical-flag .so or fails the build.
d = core.get_args_of_build("module_aiter_core")
assert d["torch_exclude"] is True and d["flags_extra_cc"] == ["-DENABLE_CK=0"], \
    f"module_aiter_core config drifted from this block's identity; re-audit: {d}"
core.build_module("module_aiter_core",
                  d["srcs"], d["flags_extra_cc"], d["flags_extra_hip"],
                  d["blob_gen_cmd"], d["extra_include"], d["extra_ldflags"],
                  d["verbose"], d["is_python_module"], d["is_standalone"],
                  d["torch_exclude"], d.get("third_party", []),
                  flags_extra_hip_per_source=d.get("flags_extra_hip_per_source"))

# build_module drops the artifact in opbd_dir and (for this entry) copies it
# to $SP/op_tests/ -- but get_module() probes get_user_jit_dir()/
# module_aiter_core.so. Place the same artifact there so the runtime adopts
# it instead of rebuilding:
src = os.path.join(core.get_user_jit_dir(), "build", "module_aiter_core",
                   "build", "module_aiter_core.so")
if not os.path.isfile(src):
    base = os.path.join(core.get_user_jit_dir(), "build", "module_aiter_core")
    found = []
    for root, _dirs, files in os.walk(base) if os.path.isdir(base) else []:
        found += [os.path.relpath(os.path.join(root, f), base) for f in files if f.endswith(".so")]
    raise SystemExit(f"aiter build left no .so at {src}; .so files found under {base}: {found}")
dst = os.path.join(core.get_user_jit_dir(), "module_aiter_core.so")
shutil.copyfile(src, dst)
assert os.path.getsize(dst) > 256 * 1024, f"baked .so implausibly small: {os.path.getsize(dst)} B"
# Note: the hipcc --offload-arch output carries no "amdhsa--gfx" marker; aiter 0.1.17
# _needs_arch_rebuild treats a marker-less .so as adopted-never-rebuilt (same class as the
# three single-target hand-compiled .so files above; a chip-marked .so built for the wrong
# arch would still be force-rebuilt in place by aiter itself, so no stale-binary wedge).
  # single-TU, CK off: ~0.7 MiB is real -- the import + dir() checks below are the true gate

# The module is the product only if it loads: prove it now, GPU-free (the .so
# init is device-independent; same reason the mxfp4 / ParoQuant import gates
# above pass in a GPU-less build):
sys.path.insert(0, os.path.dirname(dst))
_mod = importlib.import_module("module_aiter_core")
assert len(dir(_mod)) > 0, "imported module exposes no attributes -- not a pybind extension"
print(f"[build] aiter JIT pre-bake: done -- {dst} ({os.path.getsize(dst) / 1e6:.3f} MB, import-clean)")
