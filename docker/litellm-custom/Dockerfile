FROM ghcr.io/astral-sh/uv:0.11.26@sha256:3d868e555f8f1dbc324afa005066cd11e1053fc4743b9808ca8025283e65efa5 AS uvbin
FROM ghcr.io/berriai/litellm:v1.90.0

COPY --from=uvbin /uv /usr/local/bin/uv
RUN uv pip install --python /app/.venv/bin/python "mlflow>=3.1.4"
