FROM ghcr.io/astral-sh/uv:0.11.23@sha256:d0a0a753ab981624b49c97abc98821c1c09f4ca69d1ef5cee69c501be3d88479 AS uvbin
FROM ghcr.io/berriai/litellm:v1.85.1

COPY --from=uvbin /uv /usr/local/bin/uv
RUN uv pip install --python /app/.venv/bin/python "mlflow>=3.1.4"
