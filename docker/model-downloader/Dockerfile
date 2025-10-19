FROM python:3.12-slim

WORKDIR /app

RUN pip install uv

COPY pyproject.toml .

RUN uv pip sync pyproject.toml

COPY main.py .

CMD ["uv" "run" "python", "main.py"]