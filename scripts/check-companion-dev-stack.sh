#!/bin/zsh

set -euo pipefail

DEVBRIDGE_URL="${DEVBRIDGE_URL:-http://127.0.0.1:3030}"
HEALTH_URL="${HEALTH_URL:-${DEVBRIDGE_URL}/health}"
INVOKE_URL="${INVOKE_URL:-${DEVBRIDGE_URL}/invoke}"
PET_PORT="${PET_PORT:-45554}"
STT_SAMPLE_PATH="${STT_SAMPLE_PATH:-/tmp/lime-stt-test.pcm}"

section() {
  echo
  echo "== $1 =="
}

section "DevBridge"
health_json="$(curl -fsS "${HEALTH_URL}")"
echo "${health_json}"

section "ASR 凭证"
credentials_json="$(
  curl -fsS "${INVOKE_URL}" \
    -H 'Content-Type: application/json' \
    -d '{"cmd":"get_asr_credentials"}'
)"
echo "${credentials_json}"

section "桌宠连接"
pet_connections="$(lsof -nP -iTCP:${PET_PORT} 2>/dev/null || true)"
if [[ -z "${pet_connections}" ]]; then
  echo "未发现桌宠连接到 ${PET_PORT}"
else
  echo "${pet_connections}"
fi

if [[ -f "${STT_SAMPLE_PATH}" ]]; then
  section "Whisper STT"
  STT_SAMPLE_PATH="${STT_SAMPLE_PATH}" INVOKE_URL="${INVOKE_URL}" node <<'EOF'
const fs = require("fs");

async function main() {
  const samplePath = process.env.STT_SAMPLE_PATH;
  const invokeUrl = process.env.INVOKE_URL;
  const data = fs.readFileSync(samplePath);

  const response = await fetch(invokeUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      cmd: "transcribe_audio",
      args: {
        audioData: Array.from(data),
        sampleRate: 16000,
      },
    }),
  });

  const text = await response.text();
  console.log(text);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
EOF
else
  section "Whisper STT"
  echo "未找到测试音频样本：${STT_SAMPLE_PATH}"
  echo "可通过环境变量 STT_SAMPLE_PATH 指向一段 16k PCM 测试文件。"
fi
