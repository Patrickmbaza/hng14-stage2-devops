FROM python:3.12-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY worker/requirements.txt ./requirements.txt

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r requirements.txt

FROM python:3.12-slim

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --system appgroup \
    && useradd --system --gid appgroup --create-home --home-dir /home/appuser appuser

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appgroup worker /app/worker

USER appuser

HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=6 CMD python -c "import os,sys,time; path=os.getenv('WORKER_HEARTBEAT_FILE','/tmp/worker-heartbeat'); ttl=int(os.getenv('WORKER_HEARTBEAT_TTL_SECONDS','30')); sys.exit(0 if os.path.exists(path) and time.time()-os.path.getmtime(path) <= ttl else 1)"

CMD ["python", "worker/worker.py"]
