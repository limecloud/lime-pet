#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${REPO_ROOT}/dist/Lime Pet.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLIST_TEMPLATE="${SCRIPT_DIR}/Info.no-xcode.plist"
ICON_SOURCE_PATH="${REPO_ROOT}/LimePet/Resources/dewy-lime.png"
ICON_OUTPUT_PATH="${RESOURCES_DIR}/AppIcon.icns"

CONFIGURATION="debug"
VERSION=""
BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
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

if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "不支持的构建配置: ${CONFIGURATION}" >&2
  exit 1
fi

if [[ ! -f "${PLIST_TEMPLATE}" ]]; then
  echo "未找到 Info.plist 模板: ${PLIST_TEMPLATE}" >&2
  exit 1
fi

if [[ -z "${VERSION}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PLIST_TEMPLATE}")"
fi

if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${PLIST_TEMPLATE}")"
fi

generate_app_icon() {
  local source_png="$1"
  local output_icns="$2"

  if [[ ! -f "${source_png}" ]]; then
    echo "未找到应用图标源文件: ${source_png}" >&2
    return 1
  fi

  local iconset_dir
  iconset_dir="$(mktemp -d "${TMPDIR:-/tmp}/lime-pet-iconset.XXXXXX").iconset"
  mv "${iconset_dir%.iconset}" "${iconset_dir}"

  local sizes=(16 32 128 256 512)
  for size in "${sizes[@]}"; do
    sips -s format png -z "${size}" "${size}" "${source_png}" --out "${iconset_dir}/icon_${size}x${size}.png" >/dev/null

    local retina_size=$((size * 2))
    sips -s format png -z "${retina_size}" "${retina_size}" "${source_png}" --out "${iconset_dir}/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "${iconset_dir}" -o "${output_icns}"
  rm -rf "${iconset_dir}"
}

BIN_DIR="$(swift build --package-path "${REPO_ROOT}" --configuration "${CONFIGURATION}" --show-bin-path)"
find "${BIN_DIR}" -maxdepth 1 -type d -name "*.bundle" -exec rm -rf {} + 2>/dev/null || true

swift build \
  --package-path "${REPO_ROOT}" \
  --product "LimePet" \
  --configuration "${CONFIGURATION}" >&2

EXECUTABLE_PATH="${BIN_DIR}/LimePet"
RESOURCE_BUNDLE_PATH="$(find "${BIN_DIR}" -maxdepth 1 -type d -name "*.bundle" | head -n 1)"

if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
  echo "未找到可执行文件: ${EXECUTABLE_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/LimePet"
cp "${PLIST_TEMPLATE}" "${CONTENTS_DIR}/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

if [[ -n "${RESOURCE_BUNDLE_PATH}" ]]; then
  cp -R "${RESOURCE_BUNDLE_PATH}" "${APP_DIR}/"
fi

TARGET_RESOURCE_ROOT="${RESOURCES_DIR}"
if [[ -n "${RESOURCE_BUNDLE_PATH}" ]]; then
  TARGET_RESOURCE_ROOT="${APP_DIR}/$(basename "${RESOURCE_BUNDLE_PATH}")"
fi

mkdir -p "${TARGET_RESOURCE_ROOT}"
cp "${REPO_ROOT}/LimePet/Resources/character-library.json" "${TARGET_RESOURCE_ROOT}/character-library.json"
cp "${REPO_ROOT}/LimePet/Resources/live2d-model-catalog.json" "${TARGET_RESOURCE_ROOT}/live2d-model-catalog.json"
rsync -a "${REPO_ROOT}/LimePet/Resources/live2d-runtime"/ "${TARGET_RESOURCE_ROOT}/live2d-runtime"/
generate_app_icon "${ICON_SOURCE_PATH}" "${ICON_OUTPUT_PATH}"

chmod +x "${MACOS_DIR}/LimePet"

printf '%s\n' "${APP_DIR}"
