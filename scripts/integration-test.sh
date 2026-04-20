#!/usr/bin/env bash
set -euo pipefail

trap 'docker compose down -v --remove-orphans' EXIT

network_name="${COMPOSE_NETWORK_NAME:-hng-stage2-network}"

if docker network inspect "${network_name}" >/dev/null 2>&1; then
  network_containers="$(docker network inspect "${network_name}" --format '{{len .Containers}}')"
  network_label="$(docker network inspect "${network_name}" --format '{{index .Labels "com.docker.compose.network"}}')"
  if [[ "${network_containers}" == "0" && "${network_label}" != "backend" ]]; then
    docker network rm "${network_name}" >/dev/null
  fi
fi

docker compose up -d --no-build

frontend_container_id="$(docker compose ps -q frontend)"
frontend_is_healthy=0

for _ in $(seq 1 30); do
  status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${frontend_container_id}")"
  if [[ "${status}" == "healthy" ]]; then
    frontend_is_healthy=1
    break
  fi
  sleep 2
done

if [[ "${frontend_is_healthy}" -ne 1 ]]; then
  echo "frontend did not become healthy" >&2
  exit 1
fi

job_id="$(
  docker compose exec -T frontend node -e "
    fetch('http://127.0.0.1:' + process.env.FRONTEND_PORT + '/submit', { method: 'POST' })
      .then((response) => response.json())
      .then((payload) => console.log(payload.job_id));
  "
)"

if [[ -z "${job_id}" || "${job_id}" == "undefined" ]]; then
  echo "job submission did not return a valid job id" >&2
  exit 1
fi

for _ in $(seq 1 30); do
  status="$(
    docker compose exec -T frontend node -e "
      fetch('http://127.0.0.1:' + process.env.FRONTEND_PORT + '/status/${job_id}')
        .then((response) => response.json())
        .then((payload) => console.log(payload.status || ''));
    "
  )"
  if [[ "${status}" == "completed" ]]; then
    exit 0
  fi
  sleep 2
done

echo "job ${job_id} did not reach completed status" >&2
exit 1
