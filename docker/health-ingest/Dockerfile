FROM python:3.13-slim

WORKDIR /app

# Only the three runtime deps; keep the image small and the build fast.
RUN pip install --no-cache-dir fastapi uvicorn httpx

COPY main.py mapping.yaml ./

# Build-time smoke assert: the app module must import cleanly
# (mapping parses, no syntax errors). Kaniko runs this on every push.
RUN python3 -c "import main"

RUN useradd --user-group --uid 10001 app
USER app

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
