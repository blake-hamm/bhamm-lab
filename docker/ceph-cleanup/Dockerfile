# Stage 1: Builder with UV
FROM ghcr.io/astral-sh/uv:python3.12-bookworm AS builder

# Install system deps for UV and Ceph
RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
RUN uv venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# Copy dependency specs first for cache optimization
COPY pyproject.toml .

# Install dependencies with UV's full power
RUN uv pip install -r pyproject.toml --resolution=highest --no-cache

# Generate lockfile (optional but recommended)
RUN uv pip compile -o requirements.lock pyproject.toml

# --- Stage 2: Runtime ---
FROM ghcr.io/astral-sh/uv:python3.12-bookworm

# Install runtime deps
RUN apt-get update && apt-get install -y \
    ceph-common \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only what's needed
COPY --from=builder /app/.venv /app/.venv
COPY clean.py .

# Configure environment
ENV PATH="/app/.venv/bin:$PATH"
ENV CEPH_CONF=/app/result/ceph.conf
ENV CEPH_KEYRING=/app/result/ceph.client.k8s-cleaner.keyring

# Verify UV is operational
RUN uv --version && which uv

ENTRYPOINT ["python", "clean.py"]