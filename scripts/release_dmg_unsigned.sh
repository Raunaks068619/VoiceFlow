#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release_dmg_unsigned.sh --version <vX.Y.Z> [--app-path <path/to/VoiceFlow.app>]

If --app-path is not provided, the script builds Release from Xcode and uses:
  build/DerivedData/Build/Products/Release/VoiceFlow.app

Optional environment:
  XCODE_PROJECT (default: VoiceFlow.xcodeproj)
  XCODE_SCHEME  (default: VoiceFlow)
EOF
}

VERSION=""
APP_PATH=""
PROJECT="${XCODE_PROJECT:-VoiceFlow.xcodeproj}"
SCHEME="${XCODE_SCHEME:-VoiceFlow}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --app-path)
      APP_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  echo "Missing required argument: --version"
  usage
  exit 1
fi

DIST_DIR="dist"
BUILD_DIR="build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
STAGE_DIR="${BUILD_DIR}/dmg-stage"
PRODUCT_APP="${DERIVED_DATA}/Build/Products/Release/VoiceFlow.app"
DMG_PATH="${DIST_DIR}/VoiceFlow-${VERSION}-unsigned.dmg"

mkdir -p "${DIST_DIR}" "${BUILD_DIR}"
rm -rf "${STAGE_DIR}" "${DMG_PATH}"

if [[ -z "${APP_PATH}" ]]; then
  echo "==> Building Release app"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    clean build
  APP_PATH="${PRODUCT_APP}"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found: ${APP_PATH}"
  exit 1
fi

echo "==> Creating DMG staging directory"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_PATH}" "${STAGE_DIR}/VoiceFlow.app"
ln -s /Applications "${STAGE_DIR}/Applications"

# Ship the first-run helper inside the DMG so the friend can double-click it
# after dragging the app to /Applications. Strips quarantine + re-signs locally.
if [[ -f "scripts/first_run.command" ]]; then
  cp "scripts/first_run.command" "${STAGE_DIR}/First Run (fix permissions).command"
  chmod +x "${STAGE_DIR}/First Run (fix permissions).command"
fi

# Ad-hoc sign the app bundle so it has a stable identity before packaging.
# This matters: DMG contents get quarantined on download, and a machine-local
# ad-hoc signature at least prevents the "identity changed" TCC invalidation.
echo "==> Ad-hoc signing app bundle"
codesign --force --deep --options runtime --sign - "${STAGE_DIR}/VoiceFlow.app"

echo "==> Creating unsigned DMG"
hdiutil create -volname "VoiceFlow" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}"

echo "==> Writing checksum"
shasum -a 256 "${DMG_PATH}" > "${DIST_DIR}/checksums.txt"

echo "Unsigned DMG created:"
echo "  ${DMG_PATH}"
echo "Checksum:"
cat "${DIST_DIR}/checksums.txt"
