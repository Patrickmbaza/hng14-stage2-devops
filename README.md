# HNG Stage 2 DevOps

This repository contains a production-ready containerized job processing system with:

- `frontend`: Node.js UI for submitting and tracking jobs
- `api`: FastAPI service for creating jobs and returning job status
- `worker`: Python worker that processes queued jobs
- `redis`: shared queue and job-status store

## Prerequisites

- Docker Engine with Compose support
- Git
- Python 3.12+ if you want to run the API unit tests outside Docker
- Node.js 20+ if you want to run the frontend lint step outside Docker

## Setup From Scratch

1. Clone your fork:

```bash
git clone <your-fork-url>
cd hng14-stage2-devops
```

2. Create a local env file from the committed template:

```bash
cp .env.example .env
```

3. Build the images:

```bash
set -a
source .env
set +a
docker compose build
```

4. Start the full stack:

```bash
set -a
source .env
set +a
docker compose up -d
```

5. Check service health:

```bash
set -a
source .env
set +a
docker compose ps
```

You should see:

- `redis` as `healthy`
- `api` as `healthy`
- `worker` as `healthy`
- `frontend` as `healthy` or transitioning to `healthy`

6. Submit a job through the frontend:

```bash
curl -X POST http://127.0.0.1:3000/submit
```

Example response:

```json
{"job_id":"<uuid>","status":"queued"}
```

7. Poll job status:

```bash
curl http://127.0.0.1:3000/status/<uuid>
```

The status should move from `queued` to `processing` to `completed`.

8. Stop the stack:

```bash
set -a
source .env
set +a
docker compose down -v --remove-orphans
```

## Local Quality Checks

Install dependencies:

```bash
python -m pip install -r api/requirements.txt pytest pytest-cov flake8
cd frontend && npm ci && cd ..
```

Run lint:

```bash
flake8 api worker tests
cd frontend && npm run lint && cd ..
docker run --rm -i hadolint/hadolint < api/Dockerfile
docker run --rm -i hadolint/hadolint < worker/Dockerfile
docker run --rm -i hadolint/hadolint < frontend/Dockerfile
```

Run tests:

```bash
pytest --cov=api --cov-report=xml --cov-report=term-missing
```

Run the integration test:

```bash
set -a
source .env
set +a
bash scripts/integration-test.sh
```

Run the deployment script locally:

```bash
set -a
source .env
set +a
bash scripts/deploy.sh
```

The deploy script performs a health-gated rolling replacement for `api`, `worker`, and `frontend`. A candidate container must become healthy within 60 seconds before the currently running container is replaced.

## CI/CD Pipeline

GitHub Actions runs these stages in order on `ubuntu-latest`:

1. `lint`
2. `test`
3. `build`
4. `security scan`
5. `integration test`
6. `deploy` on pushes to `main` only

Pipeline details:

- Python linting uses `flake8`
- JavaScript linting uses `eslint`
- Dockerfiles are checked with `hadolint`
- API unit tests use `pytest` with mocked Redis
- Coverage is uploaded as an artifact
- Images are tagged with both `${{ github.sha }}` and `latest`
- Images are pushed to a local registry service container inside the workflow job
- Trivy runs with the current `aquasecurity/trivy-action` `v`-prefixed release tag
- Trivy fails the pipeline on any `CRITICAL` vulnerability
- Both SARIF and plain-text Trivy reports are uploaded as artifacts so findings can be inspected easily
- Integration testing brings the stack up, submits a job through the frontend, polls until completion, and tears the stack down cleanly
- Deployment is scripted and health-gated

Image hardening details:

- The Python images use Alpine-based runtime stages
- The final Python runtime images remove `pip` after dependency installation because it is not needed at runtime
- The final frontend runtime image removes `npm` and `npx` because they are not needed at runtime
- Alpine packages are upgraded during image build to reduce inherited base-image vulnerabilities

## Deploy With GitHub Actions

This repository does not need cloud credentials or deployment secrets for the stage requirements. The deploy stage runs inside GitHub Actions on `ubuntu-latest` and validates the scripted rolling update against Docker on the runner itself.

To use it in your fork:

1. Push this repository structure, including `.github/workflows/ci-cd.yml`, to your fork.
2. In GitHub, open `Settings -> Actions -> General` and make sure Actions are enabled for the repository.
3. Push a branch or open a pull request to trigger `lint`, `test`, `build`, `security_scan`, and `integration_test`.
4. Merge or push to `main` to trigger the `deploy` job after every earlier stage passes.
5. Open the Actions tab and inspect the `ci-cd` workflow run. The deploy job should show the scripted rolling deployment step succeeding only after the new containers pass health checks.

Because the deploy stage is scripted in `scripts/deploy.sh`, any push to `main` re-validates the rolling update logic automatically.

If the `security_scan` job fails, download the `trivy-text` artifact first. It contains plain-text reports for all three images and is easier to read than SARIF when you need to identify the exact package and fixed version.

## Files Added For This Stage

- `docker-compose.yml`
- `api/Dockerfile`
- `worker/Dockerfile`
- `frontend/Dockerfile`
- `.github/workflows/ci-cd.yml`
- `tests/test_api.py`
- `FIXES.md`
- `.env.example`
