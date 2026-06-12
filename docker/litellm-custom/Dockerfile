FROM ghcr.io/astral-sh/uv:0.11.21@sha256:ff07b86af50d4d9391d9daf4ff89ce427bc544f9aae87057e69a1cc0aa369946 AS uvbin
FROM ghcr.io/berriai/litellm:v1.85.1

COPY --from=uvbin /uv /usr/local/bin/uv
RUN uv pip install --python /app/.venv/bin/python "mlflow>=3.1.4"
