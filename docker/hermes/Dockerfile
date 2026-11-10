# Hermes Agent with the Hindsight memory plugin's Python dependencies baked in.
#
# The plugin declares hindsight-client/hindsight-embed in pyproject.toml and Hermes
# installs them into its own venv (marketplace docs: "installed into the Hermes venv").
# In this container that venv is /opt/hermes/.venv, which lives on the pod's overlay
# filesystem — a runtime `hermes plugins install --yes-deps` writes a separate pm
# environment under /opt/data that the sealed payload never selects, so the plugin
# fails with ModuleNotFoundError: No module named 'hindsight_client' after every
# restart. Baking them into the image is what makes memory survive pod restarts.
FROM nousresearch/hermes-agent:v0.23.1

# The image ships uv under a version-suffixed path; resolve it instead of pinning.
RUN set -eux; \
    uv=$(ls -d /opt/hermes/tools/uv-*/uv | head -1); \
    UV_CACHE_DIR=/tmp/uv-cache "$uv" pip install \
      --python /opt/hermes/.venv/bin/python \
      "hindsight-client>=0.10.1,<2" \
      "hindsight-embed>=0.10.1,<2"; \
    rm -rf /tmp/uv-cache
