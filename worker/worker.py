import os
import signal
import time
from pathlib import Path

import redis

running = True


def handle_shutdown(signum, frame):  # noqa: ARG001
    global running
    running = False


def get_redis_client() -> redis.Redis:
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "redis"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        db=int(os.getenv("REDIS_DB", "0")),
        password=os.getenv("REDIS_PASSWORD") or None,
        decode_responses=True,
    )


def get_queue_name() -> str:
    return os.getenv("JOB_QUEUE_NAME", "jobs:queue")


def get_status_key(job_id: str) -> str:
    prefix = os.getenv("JOB_STATUS_PREFIX", "job")
    return f"{prefix}:{job_id}"


def heartbeat_path() -> Path:
    return Path(os.getenv("WORKER_HEARTBEAT_FILE", "/tmp/worker-heartbeat"))


def update_heartbeat() -> None:
    heartbeat_path().write_text(str(int(time.time())), encoding="utf-8")


def process_job(redis_client: redis.Redis, job_id: str) -> None:
    print(f"Processing job {job_id}", flush=True)
    redis_client.hset(get_status_key(job_id), mapping={"status": "processing"})
    time.sleep(float(os.getenv("WORKER_JOB_DELAY_SECONDS", "2")))
    redis_client.hset(get_status_key(job_id), mapping={"status": "completed"})
    print(f"Done: {job_id}", flush=True)


def main() -> None:
    redis_client = get_redis_client()
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    while running:
        update_heartbeat()
        job = redis_client.brpop(
            get_queue_name(),
            timeout=int(os.getenv("WORKER_POLL_TIMEOUT", "5")),
        )
        if not job:
            continue
        _, job_id = job
        process_job(redis_client, job_id)


if __name__ == "__main__":
    main()
