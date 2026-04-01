#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RELEASE_DIR="${REPO_ROOT}/dist/release"

VERSION=""
BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  echo "release 打包必须提供 --version" >&2
  exit 1
fi

SANITIZED_VERSION="${VERSION#v}"
TAG_VERSION="v${SANITIZED_VERSION}"
APP_PATH="$("${SCRIPT_DIR}/build-app.sh" \
  --configuration "release" \
  --version "${SANITIZED_VERSION}" \
  --build-number "${BUILD_NUMBER}")"

ZIP_PATH="${RELEASE_DIR}/LimePet-${TAG_VERSION}-macos-unsigned.zip"
CHECKSUM_PATH="${ZIP_PATH}.sha256"

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

ditto -c -k --sequesterRsrc --keepParent \
  "${APP_PATH}" \
  "${ZIP_PATH}"

CHECKSUM="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${CHECKSUM}" "$(basename "${ZIP_PATH}")" > "${CHECKSUM_PATH}"

printf '%s\n' "${ZIP_PATH}"
