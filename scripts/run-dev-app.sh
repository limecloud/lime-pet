#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="$("${SCRIPT_DIR}/build-dev-app.sh" | tail -n 1)"

if pgrep -x "LimePet" >/dev/null 2>&1; then
  pkill -x "LimePet" || true
  sleep 1
fi

open -n "${APP_DIR}" --args "$@"
