# Apple Health Auto Export -> VictoriaMetrics ingest receiver.
#
# Multi-stage on purpose. Harbor's Trivy scan of the previous single-stage image
# reported 54 HIGH findings; 5 of them were fixable, and all 5 came from the pip
# and setuptools that the python base image ships (CVE-2025-47273 in setuptools,
# CVE-2026-114613 / GHSA-6v7p-g79w-8964 in msgpack, CVE-2026-97687 /
# CVE-2026-97689 in urllib3 — msgpack and urllib3 were present only as pip's
# own dependency tree). uv installs the same dependencies into a self-contained
# venv, so the runtime stage can delete pip, setuptools, pkg_resources and wheel
# outright and the image carries no installer at all.
#
# Every dependency ships a manylinux wheel, including ijson's bundled yajl C
# backend, so no build toolchain is needed in either stage.
#
# PSA `restricted` in the health namespace: fixed numeric UID, no shell, no home
# directory. readOnlyRootFilesystem is set in the Deployment, so nothing here
# may write outside /tmp (PYTHONDONTWRITEBYTECODE keeps .pyc writes off too).
#
# No BuildKit-only features (--mount=type=cache): nothing else in docker/ uses
# them, and the pipeline builds with plain docker build.

# Pinned tag, never :latest — the uv binary is a build input like any other.
FROM ghcr.io/astral-sh/uv:0.13.7 AS uv

FROM python:3.15-slim AS builder

COPY --from=uv /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv

WORKDIR /app

# Dependencies first: this layer is cached until pyproject.toml or uv.lock moves.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# Source second, so a code change does not re-resolve or re-download wheels.
COPY receiver ./receiver
RUN uv sync --frozen --no-dev

# Same tag as the builder: /app/.venv is a venv whose pyvenv.cfg records the
# base interpreter home, so both stages must come from the same image.
FROM python:3.15-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

# Pick up any Debian security update published after this base tag was built.
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

# Group and user share UID/GID 10001, matching the Deployment's runAsUser /
# runAsGroup / fsGroup.
RUN groupadd --gid 10001 receiver \
    && useradd --uid 10001 --gid 10001 --no-create-home \
       --shell /usr/sbin/nologin receiver

# CVE-2025-47273 and the rest live in the base image's pip/setuptools, not in
# any dependency of ours. The venv has its own interpreter, so the system
# site-packages can lose its installer entirely. The build fails here if any of
# them is still importable, so a future base image cannot regress this silently.
RUN set -eux; \
    SP="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"; \
    rm -rf \
      "$SP"/pip \
      "$SP"/pip-*.dist-info \
      "$SP"/setuptools \
      "$SP"/setuptools-*.dist-info \
      "$SP"/pkg_resources \
      "$SP"/wheel \
      "$SP"/wheel-*.dist-info \
      "$SP"/_distutils_hack \
      "$SP"/distutils-precedence.pth \
      /usr/local/bin/pip \
      /usr/local/bin/pip3 \
      /usr/local/bin/pip3.*; \
    python -c 'import importlib.util as u, sys; \
missing = [m for m in ("pip", "setuptools", "pkg_resources", "wheel") if u.find_spec(m)]; \
print("still importable: " + ", ".join(missing)) if missing else print("pip/setuptools/pkg_resources/wheel: absent"); \
sys.exit(1 if missing else 0)'

# Only the venv and the package: no build cache, no uv binary, no pip.
COPY --from=builder --chown=10001:10001 /app /app

# Each FROM resets the working directory, so the builder's WORKDIR /app does not
# carry over. uvicorn resolves "receiver.app" relative to cwd, so the runtime
# stage needs it back explicitly.
WORKDIR /app

# A module-path regression must fail the build, not the pod: this exercises the
# same import path uvicorn uses at startup.
RUN /app/.venv/bin/python -c "import receiver.app"

USER 10001

EXPOSE 8080

# --no-access-log: the receiver must emit exactly ONE INFO line per accepted
# POST (the structural fingerprint log); uvicorn's access log would add a
# second line per request and has no value here.
# --app-dir /app makes the import root explicit, so the app is importable
# regardless of the working directory.
CMD ["uvicorn", "receiver.app:app", "--app-dir", "/app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
