#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  COMPOSE_NETWORK_NAME
  REDIS_IMAGE
  REDIS_HOST
  REDIS_PORT
  REDIS_DB
  REDIS_PASSWORD
  JOB_QUEUE_NAME
  JOB_STATUS_PREFIX
  API_IMAGE
  API_HOST
  API_PORT
  WORKER_IMAGE
  WORKER_POLL_TIMEOUT
  WORKER_JOB_DELAY_SECONDS
  WORKER_HEARTBEAT_FILE
  WORKER_HEARTBEAT_TTL_SECONDS
  FRONTEND_IMAGE
  API_BASE_URL
  FRONTEND_HOST
  FRONTEND_PORT
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "missing required environment variable: ${var_name}" >&2
    exit 1
  fi
done

network_name="${COMPOSE_NETWORK_NAME}"

wait_for_health() {
  local container_name="$1"
  local deadline=$((SECONDS + 60))

  while (( SECONDS < deadline )); do
    local status
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container_name}")"
    if [[ "${status}" == "healthy" ]]; then
      return 0
    fi
    if [[ "${status}" == "unhealthy" ]]; then
      return 1
    fi
    sleep 2
  done

  return 1
}

ensure_network() {
  docker network inspect "${network_name}" >/dev/null 2>&1 || docker network create --internal "${network_name}" >/dev/null
}

container_exists() {
  docker inspect "$1" >/dev/null 2>&1
}

remove_container() {
  docker rm -f "$1" >/dev/null 2>&1 || true
}

ensure_redis() {
  if ! container_exists redis; then
    docker run -d \
      --name redis \
      --network "${network_name}" \
      --network-alias redis \
      -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
      --health-cmd 'redis-cli -a "$REDIS_PASSWORD" ping | grep PONG' \
      --health-interval 10s \
      --health-timeout 5s \
      --health-retries 10 \
      --health-start-period 10s \
      "${REDIS_IMAGE}" \
      redis-server --appendonly yes --requirepass "${REDIS_PASSWORD}" >/dev/null
  fi

  docker start redis >/dev/null 2>&1 || true
  if ! wait_for_health redis; then
    echo "redis failed health check" >&2
    exit 1
  fi
}

run_candidate() {
  local service="$1"
  local image="$2"
  shift 2
  local candidate="candidate-${service}"

  remove_container "${candidate}"
  docker run -d --name "${candidate}" --network "${network_name}" "$@" "${image}" >/dev/null

  if ! wait_for_health "${candidate}"; then
    echo "${service} candidate failed health check" >&2
    docker logs "${candidate}" || true
    remove_container "${candidate}"
    exit 1
  fi
}

restore_previous() {
  local service="$1"
  local previous="previous-${service}"

  if ! container_exists "${previous}"; then
    return 0
  fi

  docker network connect --alias "${service}" "${network_name}" "${previous}" >/dev/null 2>&1 || true
  docker start "${previous}" >/dev/null
  docker rename "${previous}" "${service}"
}

deploy_service() {
  local service="$1"
  local image="$2"
  local candidate_port_arg="$3"
  local live_port_arg="$4"
  shift 4
  local env_args=("$@")
  local candidate="candidate-${service}"
  local previous="previous-${service}"
  local had_previous=0
  local candidate_run_args=()
  local live_run_args=()

  if [[ -n "${candidate_port_arg}" ]]; then
    candidate_run_args+=(-p "${candidate_port_arg}")
  fi

  if [[ -n "${live_port_arg}" ]]; then
    live_run_args+=(-p "${live_port_arg}")
  fi

  remove_container "${previous}"
  run_candidate "${service}" "${image}" "${candidate_run_args[@]}" "${env_args[@]}"

  if container_exists "${service}"; then
    had_previous=1
    docker stop "${service}" >/dev/null
    docker rename "${service}" "${previous}"
    docker network disconnect "${network_name}" "${previous}" >/dev/null 2>&1 || true
  fi

  if ! docker run -d \
    --name "${service}" \
    --network "${network_name}" \
    --network-alias "${service}" \
    "${live_run_args[@]}" \
    "${env_args[@]}" \
    "${image}" >/dev/null; then
    echo "failed to start ${service} live container" >&2
    remove_container "${service}"
    remove_container "${candidate}"
    if (( had_previous == 1 )); then
      restore_previous "${service}"
    fi
    exit 1
  fi

  if ! wait_for_health "${service}"; then
    echo "${service} failed post-promotion health check" >&2
    docker logs "${service}" || true
    remove_container "${service}"
    remove_container "${candidate}"
    if (( had_previous == 1 )); then
      restore_previous "${service}"
    fi
    exit 1
  fi

  remove_container "${candidate}"
  remove_container "${previous}"
}

deploy_api() {
  local env_args=(
    -e REDIS_HOST="${REDIS_HOST}"
    -e REDIS_PORT="${REDIS_PORT}"
    -e REDIS_DB="${REDIS_DB}"
    -e REDIS_PASSWORD="${REDIS_PASSWORD}"
    -e JOB_QUEUE_NAME="${JOB_QUEUE_NAME}"
    -e JOB_STATUS_PREFIX="${JOB_STATUS_PREFIX}"
    -e API_HOST="${API_HOST}"
    -e API_PORT="${API_PORT}"
  )
  deploy_service api "${API_IMAGE}" "" "" "${env_args[@]}"
}

deploy_worker() {
  local env_args=(
    -e REDIS_HOST="${REDIS_HOST}"
    -e REDIS_PORT="${REDIS_PORT}"
    -e REDIS_DB="${REDIS_DB}"
    -e REDIS_PASSWORD="${REDIS_PASSWORD}"
    -e JOB_QUEUE_NAME="${JOB_QUEUE_NAME}"
    -e JOB_STATUS_PREFIX="${JOB_STATUS_PREFIX}"
    -e WORKER_POLL_TIMEOUT="${WORKER_POLL_TIMEOUT}"
    -e WORKER_JOB_DELAY_SECONDS="${WORKER_JOB_DELAY_SECONDS}"
    -e WORKER_HEARTBEAT_FILE="${WORKER_HEARTBEAT_FILE}"
    -e WORKER_HEARTBEAT_TTL_SECONDS="${WORKER_HEARTBEAT_TTL_SECONDS}"
  )
  deploy_service worker "${WORKER_IMAGE}" "" "" "${env_args[@]}"
}

deploy_frontend() {
  local env_args=(
    -e API_BASE_URL="${API_BASE_URL}"
    -e FRONTEND_HOST="${FRONTEND_HOST}"
    -e FRONTEND_PORT="${FRONTEND_PORT}"
  )
  deploy_service frontend "${FRONTEND_IMAGE}" "127.0.0.1::${FRONTEND_PORT}" "${FRONTEND_PORT}:${FRONTEND_PORT}" "${env_args[@]}"
}

ensure_network
ensure_redis
deploy_api
deploy_worker
deploy_frontend
