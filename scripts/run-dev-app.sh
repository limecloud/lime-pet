#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="$("${SCRIPT_DIR}/build-dev-app.sh" | tail -n 1)"
CONTROL_PLANE_BASE_URL="${LIME_CONTROL_PLANE_BASE_URL:-http://127.0.0.1:8080}"
TENANT_ID="${LIME_TENANT_ID:-tenant-0001}"
DISABLE_CONTROL_PLANE="${LIME_DISABLE_CONTROL_PLANE:-0}"

has_flag() {
  local flag="$1"
  shift
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "${flag}" ]]; then
      return 0
    fi
  done
  return 1
}

if pgrep -x "LimePet" >/dev/null 2>&1; then
  pkill -x "LimePet" || true
  sleep 1
fi

LAUNCH_ARGS=("$@")

if [[ "${DISABLE_CONTROL_PLANE}" != "1" ]]; then
  if [[ -n "${CONTROL_PLANE_BASE_URL}" ]] && ! has_flag "--control-plane-base-url" "${LAUNCH_ARGS[@]}"; then
    LAUNCH_ARGS+=("--control-plane-base-url" "${CONTROL_PLANE_BASE_URL}")
  fi

  if [[ -n "${TENANT_ID}" ]] && ! has_flag "--tenant-id" "${LAUNCH_ARGS[@]}"; then
    LAUNCH_ARGS+=("--tenant-id" "${TENANT_ID}")
  fi
fi

open -n "${APP_DIR}" --args "${LAUNCH_ARGS[@]}"
