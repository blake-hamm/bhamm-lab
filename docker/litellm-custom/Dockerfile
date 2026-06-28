FROM ghcr.io/astral-sh/uv:0.11.25@sha256:1e3808aa9023d0980e7c15b1fa7c1ac16ff35925780cf5c459858b2d693f01a9 AS uvbin
FROM ghcr.io/berriai/litellm:v1.90.0

COPY --from=uvbin /uv /usr/local/bin/uv
RUN uv pip install --python /app/.venv/bin/python "mlflow>=3.1.4"
