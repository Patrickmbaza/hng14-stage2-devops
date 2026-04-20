import asyncio
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from api.main import create_app


def get_route_handler(app, path: str, method: str):
    for route in app.router.routes:
        if route.path == path and method in route.methods:
            return route.endpoint
    raise AssertionError(f"route not found: {method} {path}")


def make_app(redis_client: MagicMock):
    with patch("api.main.get_redis_client", return_value=redis_client):
        return create_app()


def test_create_job_queues_job_and_returns_identifier() -> None:
    redis_client = MagicMock()
    app = make_app(redis_client)
    handler = get_route_handler(app, "/jobs", "POST")

    payload = asyncio.run(handler())

    assert "job_id" in payload
    assert payload["status"] == "queued"
    redis_client.hset.assert_called_once()
    redis_client.lpush.assert_called_once()


def test_get_job_returns_current_status() -> None:
    redis_client = MagicMock()
    redis_client.hget.return_value = "completed"
    app = make_app(redis_client)
    handler = get_route_handler(app, "/jobs/{job_id}", "GET")

    payload = asyncio.run(handler("job-123"))

    assert payload == {"job_id": "job-123", "status": "completed"}


def test_get_job_returns_not_found_for_unknown_job() -> None:
    redis_client = MagicMock()
    redis_client.hget.return_value = None
    app = make_app(redis_client)
    handler = get_route_handler(app, "/jobs/{job_id}", "GET")

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(handler("missing-job"))

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "job not found"


def test_healthcheck_pings_redis() -> None:
    redis_client = MagicMock()
    app = make_app(redis_client)
    handler = get_route_handler(app, "/health", "GET")

    payload = asyncio.run(handler())

    assert payload == {"status": "ok"}
    redis_client.ping.assert_called_once_with()
