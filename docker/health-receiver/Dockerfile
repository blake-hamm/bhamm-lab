# Apple Health Auto Export -> VictoriaMetrics ingest receiver.
#
# python:3.13-slim: every dependency (fastapi, uvicorn, httpx, ijson) ships a
# manylinux wheel, so there is no build toolchain in the final layer. ijson's
# wheel carries the bundled yajl C backend, which is what keeps the streaming
# parse fast (verified: ijson.backend == yajl2_c).
#
# PSA `restricted` in the health namespace: fixed numeric UID, no shell, no
# home directory. readOnlyRootFilesystem is set in the Deployment, so nothing
# here may write outside /tmp.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY receiver ./receiver

RUN useradd --uid 10001 --no-create-home --no-user-group \
    --shell /usr/sbin/nologin receiver

USER 10001

EXPOSE 8080

# --no-access-log: the receiver must emit exactly ONE INFO line per accepted
# POST (the structural fingerprint log); uvicorn's access log would add a
# second line per request and has no value here.
CMD ["uvicorn", "receiver.app:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
