#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PET_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

resolve_default_lime_root() {
  local candidate
  for candidate in \
    "${PET_ROOT}/../../aiclientproxy/lime" \
    "${PET_ROOT}/../aiclientproxy/lime"
  do
    if [[ -f "${candidate}/src-tauri/Cargo.toml" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  echo "${PET_ROOT}/../../aiclientproxy/lime"
}

DEFAULT_LIME_ROOT="$(resolve_default_lime_root)"
LIME_ROOT="${LIME_ROOT:-${DEFAULT_LIME_ROOT}}"
LIME_MANIFEST_PATH="${LIME_ROOT}/src-tauri/Cargo.toml"
LIME_TARGET_DIR="${LIME_TARGET_DIR:-/tmp/lime-whisper-target}"
LIME_LOG_PATH="${LIME_LOG_PATH:-/tmp/lime-companion-dev.log}"
LIME_PID_PATH="${LIME_PID_PATH:-/tmp/lime-companion-dev.pid}"
LIME_BUILD_JOBS="${LIME_BUILD_JOBS:-8}"
LIME_HEALTH_URL="${LIME_HEALTH_URL:-http://127.0.0.1:3030/health}"

if [[ ! -f "${LIME_MANIFEST_PATH}" ]]; then
  echo "未找到 lime 宿主工程：${LIME_MANIFEST_PATH}" >&2
  echo "可以通过环境变量 LIME_ROOT 指向 lime 仓库根目录。" >&2
  exit 1
fi

wait_for_lime() {
  local attempts="${1:-40}"
  local delay="${2:-0.5}"
  local index

  for ((index = 1; index <= attempts; index++)); do
    if curl -fsS "${LIME_HEALTH_URL}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay}"
  done

  return 1
}

record_lime_pid() {
  local pids
  pids="$(
    {
      lsof -tiTCP:3030 -sTCP:LISTEN 2>/dev/null || true
      lsof -tiTCP:45554 -sTCP:LISTEN 2>/dev/null || true
    } | sort -u
  )"

  if [[ -n "${pids}" ]]; then
    printf "%s\n" "${pids}" >"${LIME_PID_PATH}"
  fi
}

stop_existing_lime() {
  local pids
  pids="$(
    {
      lsof -tiTCP:3030 -sTCP:LISTEN 2>/dev/null || true
      lsof -tiTCP:45554 -sTCP:LISTEN 2>/dev/null || true
    } | sort -u
  )"

  if [[ -n "${pids}" ]]; then
    echo "[lime] 停止旧宿主进程: ${pids}"
    kill ${=pids} 2>/dev/null || true
    sleep 1
  fi
}

start_lime_detached() {
  local lime_bin="${1}"

  rm -f "${LIME_LOG_PATH}" "${LIME_PID_PATH}"
  nohup "${lime_bin}" >"${LIME_LOG_PATH}" 2>&1 &
}

start_lime_in_terminal() {
  local lime_bin="${1}"
  local escaped_bin escaped_log

  escaped_bin="${lime_bin//\"/\\\"}"
  escaped_log="${LIME_LOG_PATH//\"/\\\"}"

  if ! command -v osascript >/dev/null 2>&1; then
    echo "nohup 启动失败，且当前系统没有 osascript，无法自动打开 Terminal 保持宿主。" >&2
    return 1
  fi

  osascript >/dev/null <<EOF
tell application "Terminal"
  activate
  do script "exec \"${escaped_bin}\" >> \"${escaped_log}\" 2>&1"
end tell
EOF
}

echo "[1/3] 构建 lime 宿主（local-whisper）..."
CARGO_TARGET_DIR="${LIME_TARGET_DIR}" cargo build -j "${LIME_BUILD_JOBS}" --features local-whisper --manifest-path "${LIME_MANIFEST_PATH}"

LIME_BIN="${LIME_TARGET_DIR}/debug/lime"
if [[ ! -x "${LIME_BIN}" ]]; then
  echo "构建完成，但未找到可执行文件：${LIME_BIN}" >&2
  exit 1
fi

echo "[2/3] 重启 lime 宿主..."
stop_existing_lime
if [[ "$(uname -s)" == "Darwin" ]]; then
  start_lime_in_terminal "${LIME_BIN}"
  if ! wait_for_lime 60 0.5; then
    echo "[lime] 宿主启动失败，最近日志：" >&2
    tail -n 120 "${LIME_LOG_PATH}" 2>/dev/null || true
    exit 1
  fi
else
  start_lime_detached "${LIME_BIN}"
  if ! wait_for_lime 30 0.5; then
    echo "[lime] 宿主启动失败，最近日志：" >&2
    tail -n 120 "${LIME_LOG_PATH}" 2>/dev/null || true
    exit 1
  fi
fi

record_lime_pid

echo "[3/3] 启动 LimePet..."
"${SCRIPT_DIR}/run-dev-app.sh" "$@"

echo
echo "Lime 宿主已就绪：${LIME_HEALTH_URL}"
echo "Lime 宿主日志：${LIME_LOG_PATH}"
echo "Lime 宿主 PID 文件：${LIME_PID_PATH}"
