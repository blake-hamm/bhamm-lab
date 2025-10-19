FROM ghcr.io/astral-sh/uv:alpine

ADD . /app

WORKDIR /app

RUN uv sync --locked

CMD ["uv" "run" "python", "main.py"]