#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RELEASE_DIR="${REPO_ROOT}/dist/release"

VERSION=""
BUILD_NUMBER=""
ARTIFACT_SUFFIX=""

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
    --artifact-suffix)
      ARTIFACT_SUFFIX="$2"
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

if [[ -z "${ARTIFACT_SUFFIX}" ]]; then
  case "$(uname -m)" in
    arm64|aarch64)
      ARTIFACT_SUFFIX="macos-arm64"
      ;;
    x86_64|amd64)
      ARTIFACT_SUFFIX="macos-x64"
      ;;
    *)
      ARTIFACT_SUFFIX="macos-$(uname -m)"
      ;;
  esac
fi

SANITIZED_VERSION="${VERSION#v}"
TAG_VERSION="v${SANITIZED_VERSION}"
APP_PATH="$("${SCRIPT_DIR}/build-app.sh" \
  --configuration "release" \
  --version "${SANITIZED_VERSION}" \
  --build-number "${BUILD_NUMBER}")"

ZIP_PATH="${RELEASE_DIR}/LimePet-${TAG_VERSION}-${ARTIFACT_SUFFIX}-unsigned.zip"
ZIP_CHECKSUM_PATH="${ZIP_PATH}.sha256"
DMG_PATH="${RELEASE_DIR}/LimePet-${TAG_VERSION}-${ARTIFACT_SUFFIX}.dmg"
DMG_CHECKSUM_PATH="${DMG_PATH}.sha256"
DMG_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lime-pet-dmg.XXXXXX")"
DMG_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lime-pet-dmg-work.XXXXXX")"
DMG_RW_PATH="${DMG_WORK_DIR}/LimePet-${TAG_VERSION}-${ARTIFACT_SUFFIX}-temp.sparseimage"

cleanup() {
  rm -rf "${DMG_STAGE_DIR}"
  rm -rf "${DMG_WORK_DIR}"
}

trap cleanup EXIT

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

ditto -c -k --sequesterRsrc --keepParent \
  "${APP_PATH}" \
  "${ZIP_PATH}"

ZIP_CHECKSUM="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${ZIP_CHECKSUM}" "$(basename "${ZIP_PATH}")" > "${ZIP_CHECKSUM_PATH}"

cp -R "${APP_PATH}" "${DMG_STAGE_DIR}/Lime Pet.app"

hdiutil create \
  -volname "Lime Pet" \
  -srcfolder "${DMG_STAGE_DIR}" \
  -fs HFS+ \
  -format UDSP \
  -ov \
  "${DMG_RW_PATH}" >/dev/null

hdiutil convert \
  "${DMG_RW_PATH}" \
  -format UDZO \
  -ov \
  -o "${DMG_PATH}" >/dev/null

DMG_CHECKSUM="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${DMG_CHECKSUM}" "$(basename "${DMG_PATH}")" > "${DMG_CHECKSUM_PATH}"

printf '%s\n' "${ZIP_PATH}"
printf '%s\n' "${DMG_PATH}"
