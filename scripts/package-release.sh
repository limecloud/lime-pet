#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RELEASE_DIR="${REPO_ROOT}/dist/release"
APPLE_SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

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

is_signing_enabled() {
  [[ -n "${APPLE_SIGNING_IDENTITY}" ]]
}

is_notarization_enabled() {
  [[ -n "${APPLE_SIGNING_IDENTITY}" && -n "${APPLE_TEAM_ID}" && -n "${APPLE_ID}" && -n "${APPLE_APP_SPECIFIC_PASSWORD}" ]]
}

sign_path() {
  local target_path="$1"

  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${APPLE_SIGNING_IDENTITY}" \
    "${target_path}"
}

sign_app_bundle() {
  local app_path="$1"

  if ! is_signing_enabled; then
    echo "[release] 未配置 APPLE_SIGNING_IDENTITY，继续产出未签名 macOS dmg。" >&2
    return 0
  fi

  echo "[release] 正在签名 app bundle: ${app_path}" >&2
  sign_path "${app_path}"
  codesign --verify --deep --strict --verbose=2 "${app_path}"
}

sign_disk_image() {
  local dmg_path="$1"

  if ! is_signing_enabled; then
    return 0
  fi

  echo "[release] 正在签名 dmg: ${dmg_path}" >&2
  sign_path "${dmg_path}"
  codesign --verify --verbose=2 "${dmg_path}"
}

notarize_disk_image() {
  local dmg_path="$1"

  if ! is_signing_enabled; then
    return 0
  fi

  if ! is_notarization_enabled; then
    echo "[release] 已签名 dmg，但未配置完整 notarization 凭据，跳过 notarize/staple。" >&2
    return 0
  fi

  echo "[release] 正在 notarize dmg: ${dmg_path}" >&2
  xcrun notarytool submit \
    "${dmg_path}" \
    --apple-id "${APPLE_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait

  echo "[release] 正在 staple dmg: ${dmg_path}" >&2
  xcrun stapler staple "${dmg_path}"
  spctl --assess --type open --verbose=4 "${dmg_path}"
}

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

sign_app_bundle "${APP_PATH}"

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

sign_disk_image "${DMG_PATH}"
notarize_disk_image "${DMG_PATH}"

DMG_CHECKSUM="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${DMG_CHECKSUM}" "$(basename "${DMG_PATH}")" > "${DMG_CHECKSUM_PATH}"

printf '%s\n' "${ZIP_PATH}"
printf '%s\n' "${DMG_PATH}"
