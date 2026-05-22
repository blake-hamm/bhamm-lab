FROM ghcr.io/astral-sh/uv:0.11.7 AS uvbin
FROM ghcr.io/berriai/litellm:v1.85.1

COPY --from=uvbin /uv /usr/local/bin/uv
RUN uv pip install --python /app/.venv/bin/python "mlflow>=3.1.4"
