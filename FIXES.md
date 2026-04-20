# FIXES

## Starter Issues Fixed

1. `api/.env:1-2`
   Problem: A tracked `.env` file was committed to the repository and included a real-looking secret placeholder.
   Fix: Removed `api/.env`, added ignore rules in `.gitignore`, and replaced it with a safe root `.env.example`.

2. `api/main.py:8`
   Problem: Redis was hardcoded to `localhost:6379`, which breaks container-to-container communication.
   Fix: Replaced hardcoded Redis connection settings with environment-driven configuration.

3. `api/main.py:10-15`
   Problem: Job creation pushed to a hardcoded queue name and returned only the job ID.
   Fix: Made queue naming configurable, stored status deterministically, and returned both `job_id` and initial `queued` status with HTTP `201`.

4. `api/main.py:17-22`
   Problem: Missing jobs returned a JSON error payload with HTTP `200` instead of a real `404`.
   Fix: Raised `HTTPException(status_code=404)` for unknown jobs.

5. `api/main.py:17-22`
   Problem: Response handling depended on manual byte decoding from Redis.
   Fix: Enabled `decode_responses=True` in the Redis client and removed manual decoding.

6. `api/main.py:1-22`
   Problem: The API had no health endpoint, which prevented a proper container `HEALTHCHECK` and health-gated startup.
   Fix: Added `/health` and used it in Docker and Compose health checks.

7. `worker/worker.py:6`
   Problem: The worker also hardcoded Redis to `localhost:6379`.
   Fix: Switched to environment-driven Redis configuration.

8. `worker/worker.py:8-18`
   Problem: The worker used a hardcoded queue name and only ever wrote `completed`, so there was no visible in-progress state.
   Fix: Made queue and key prefixes configurable and added a `processing` status before completion.

9. `worker/worker.py:1-18`
   Problem: The worker had no graceful shutdown handling or heartbeat, so container health and controlled termination were missing.
   Fix: Added signal handling, heartbeat file updates, and a worker health check based on heartbeat freshness.

10. `frontend/app.js:6`
    Problem: The frontend called `http://localhost:8000`, which fails inside containers.
    Fix: Replaced it with the environment-driven `API_BASE_URL`.

11. `frontend/app.js:11-26`
    Problem: Frontend proxy handlers always returned a generic `500`, masking upstream API failures.
    Fix: Preserved upstream status codes where available and returned clearer error messages.

12. `frontend/app.js:29-30`
    Problem: The frontend listened on a hardcoded port and host.
    Fix: Added `FRONTEND_HOST` and `FRONTEND_PORT` environment support.

13. `frontend/app.js:8-30`
    Problem: The frontend had no `/health` endpoint for container health checks.
    Fix: Added `/health`.

14. `frontend/app.js:8-30`
    Problem: The app relied only on static file serving and did not explicitly serve `/`.
    Fix: Added a dedicated `/` handler that serves `views/index.html`.

15. `frontend/package.json:5-10`
    Problem: The frontend had no lint script, no eslint configuration, and no lockfile for reproducible installs.
    Fix: Added `npm run lint`, committed `.eslintrc.json`, and generated `frontend/package-lock.json`.

16. `README.md:1`
    Problem: The starter README contained only the repository title and no usable setup or operations documentation.
    Fix: Rewrote `README.md` with prerequisites, startup commands, verification steps, CI/CD details, and deploy usage.

## Missing Production Requirements Added

17. `api/Dockerfile` (new file)
    Problem: The API service was not containerized.
    Fix: Added a multi-stage, non-root production Dockerfile with a working `HEALTHCHECK`.

18. `worker/Dockerfile` (new file)
    Problem: The worker service was not containerized.
    Fix: Added a multi-stage, non-root production Dockerfile with a heartbeat-based `HEALTHCHECK`.

19. `frontend/Dockerfile` (new file)
    Problem: The frontend service was not containerized.
    Fix: Added a multi-stage, non-root production Dockerfile with a working `HEALTHCHECK`.

20. `docker-compose.yml` (new file)
    Problem: There was no full-stack orchestration for local or CI environments.
    Fix: Added Compose orchestration with a named internal network, health-gated dependencies, env-driven configuration, no host Redis exposure, and CPU/memory limits for every service.

21. `.github/workflows/ci-cd.yml` (new file)
    Problem: No CI/CD pipeline existed.
    Fix: Added a GitHub Actions workflow that runs `lint -> test -> build -> security scan -> integration test -> deploy` in order.

22. `tests/test_api.py` (new file)
    Problem: The API had no unit tests.
    Fix: Added four pytest unit tests with mocked Redis covering job creation, lookup, not-found handling, and health checks.

23. `scripts/integration-test.sh` (new file)
    Problem: There was no automated end-to-end validation of the full stack.
    Fix: Added a script that brings the stack up, submits a job through the frontend, polls until completion, and always tears the stack down.

24. `scripts/deploy.sh` (new file)
    Problem: There was no scripted deployment or rolling update path.
    Fix: Added a health-gated rolling deployment script that validates candidate containers before replacing the running ones.

25. `.env.example` (new file)
    Problem: There was no committed environment template listing the variables required to run the system.
    Fix: Added `.env.example` with placeholders/defaults for application, Compose, image, and resource-limit settings.

26. `api/Dockerfile:36`
    Problem: The API image always started Uvicorn on hardcoded `0.0.0.0:8000`, so changing `API_PORT` or `API_HOST` in Compose or deployment envs did not actually change the listener.
    Fix: Changed the container command to read `API_HOST` and `API_PORT` from the runtime environment.

27. `.github/workflows/ci-cd.yml:40-246`
    Problem: The workflow was implemented as one long job, which made the required `lint -> test -> build -> security scan -> integration test -> deploy` stage gating implicit instead of enforced by job dependencies.
    Fix: Split the pipeline into six explicit jobs connected with `needs`, while preserving artifact handoff between stages.

28. `.github/workflows/ci-cd.yml:107-246`
    Problem: Images built in one GitHub Actions job do not exist automatically in later jobs, so scan, integration, and deploy stages would not have reliable access to the build outputs.
    Fix: Added image export with `docker save`, uploaded the archives as artifacts, and loaded them back in downstream jobs.

29. `scripts/deploy.sh:1-225`
    Problem: The original deploy flow deleted the running service during promotion and did not preserve a rollback path if the promoted container failed after the switch.
    Fix: Reworked deployment to validate a candidate first, keep the previous container recoverable during the handoff, and restore it if the promoted container fails its health check.

30. `scripts/integration-test.sh:1-63`
    Problem: The integration test could continue after an unhealthy frontend startup or an empty submission response, producing misleading failures later in the script.
    Fix: Added explicit checks for frontend health and for a valid returned `job_id` before polling status.

31. `pytest.ini:1-2`
    Problem: GitHub Actions test collection could not import `api.main` because the repository root was not guaranteed to be on Python's import path.
    Fix: Added `pythonpath = .` so pytest resolves the local `api` package consistently in CI.

32. `.github/workflows/ci-cd.yml:158-198`
    Problem: The workflow referenced `aquasecurity/trivy-action@0.30.0`, which GitHub could not resolve.
    Fix: Updated the scan steps to a valid `v`-prefixed Trivy action release.

33. `.github/workflows/ci-cd.yml:158-234`
    Problem: When Trivy failed, the workflow stopped with only a generic final error line, making it hard to identify the exact vulnerable packages from the Actions UI.
    Fix: Kept the failing gate but added always-uploaded plain-text Trivy reports alongside SARIF artifacts.

34. `api/Dockerfile:1-39`
    Problem: The API runtime image still contained `pip`, which Trivy reported even though package-install tooling is not needed in production containers.
    Fix: Removed `pip` from both the build venv after dependency installation and from the final runtime image.

35. `worker/Dockerfile:1-38`
    Problem: The worker runtime image also shipped with `pip`, creating unnecessary scan surface and unused package-management tooling in production.
    Fix: Removed `pip` from both the build venv after dependency installation and from the final runtime image.

36. `frontend/Dockerfile:1-27`
    Problem: The frontend runtime image still included bundled `npm` and `npx`, and Trivy findings were coming from that package-manager dependency tree rather than the application itself.
    Fix: Removed `npm`, `npx`, and the bundled `npm` directory from the final runtime image.

37. `api/Dockerfile:16-25`, `worker/Dockerfile:16-24`, `frontend/Dockerfile:13-17`
    Problem: Base-image packages could remain behind the latest Alpine security patches at build time, causing avoidable image-scan findings.
    Fix: Added `apk upgrade --no-cache` in the final runtime stages to bring Alpine packages up to date during image build.
