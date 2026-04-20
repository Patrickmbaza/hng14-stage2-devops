import os
import uuid
from typing import Any

import redis
from fastapi import FastAPI, HTTPException


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


def create_app() -> FastAPI:
    application = FastAPI()
    application.state.redis = get_redis_client()

    @application.get("/health")
    async def healthcheck() -> dict[str, str]:
        application.state.redis.ping()
        return {"status": "ok"}

    @application.post("/jobs", status_code=201)
    async def create_job() -> dict[str, str]:
        job_id = str(uuid.uuid4())
        redis_client = application.state.redis
        redis_client.hset(get_status_key(job_id), mapping={"status": "queued"})
        redis_client.lpush(get_queue_name(), job_id)
        return {"job_id": job_id, "status": "queued"}

    @application.get("/jobs/{job_id}")
    async def get_job(job_id: str) -> dict[str, Any]:
        status = application.state.redis.hget(get_status_key(job_id), "status")
        if status is None:
            raise HTTPException(status_code=404, detail="job not found")
        return {"job_id": job_id, "status": status}

    return application


app = create_app()
