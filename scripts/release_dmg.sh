#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# VoiceFlow Release Build Script
# -----------------------------------------------------------------------------
#
# Usage:
#   scripts/release_dmg.sh --version <vX.Y.Z>
#
# Behavior:
#   Auto-detects whether Developer ID signing is configured (via env vars).
#   - If configured: signs with Developer ID, submits for notarization,
#     staples the ticket, creates a signed DMG that "just works" for end users.
#   - If not configured: falls back to ad-hoc signing (local testing only).
#
# Required for signed/notarized builds:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)"
#   NOTARIZE_APPLE_ID="you@apple.com"
#   NOTARIZE_TEAM_ID="TEAM_ID"
#   NOTARIZE_PASSWORD="app-specific-password"       # from appleid.apple.com
#     OR
#   NOTARIZE_KEYCHAIN_PROFILE="voiceflow-notarize"  # after xcrun notarytool store-credentials
#
# See scripts/README_SIGNING.md for setup instructions.
# -----------------------------------------------------------------------------

VERSION=""
APP_PATH=""
PROJECT="${XCODE_PROJECT:-VoiceFlow.xcodeproj}"
SCHEME="${XCODE_SCHEME:-VoiceFlow}"

usage() {
  cat <<'EOF'
Usage:
  scripts/release_dmg.sh --version <vX.Y.Z> [--app-path <path/to/VoiceFlow.app>]

Environment variables for signed/notarized builds (all optional):
  DEVELOPER_ID                   Full identity name (e.g. "Developer ID Application: Jane Doe (ABC123)")
  NOTARIZE_APPLE_ID              Apple ID email
  NOTARIZE_TEAM_ID               Developer team ID
  NOTARIZE_PASSWORD              App-specific password
  NOTARIZE_KEYCHAIN_PROFILE      Alternative: keychain profile name

If no Developer ID is configured, script falls back to ad-hoc signing
(builds still work locally, but end users will see Gatekeeper warnings).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)    VERSION="${2:-}"; shift 2 ;;
    --app-path)   APP_PATH="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  echo "Missing required argument: --version"
  usage
  exit 1
fi

# -----------------------------------------------------------------------------
# Detect signing mode
# -----------------------------------------------------------------------------

SIGNING_MODE="adhoc"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  if [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]] || \
     ( [[ -n "${NOTARIZE_APPLE_ID:-}" ]] && [[ -n "${NOTARIZE_TEAM_ID:-}" ]] && [[ -n "${NOTARIZE_PASSWORD:-}" ]] ); then
    SIGNING_MODE="notarized"
  else
    SIGNING_MODE="signed_only"
    echo "WARNING: DEVELOPER_ID set but notarization credentials missing."
    echo "         Building signed-but-not-notarized DMG. Gatekeeper will still warn."
  fi
fi

echo "==> Signing mode: ${SIGNING_MODE}"

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

DIST_DIR="dist"
BUILD_DIR="build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
STAGE_DIR="${BUILD_DIR}/dmg-stage"
PRODUCT_APP="${DERIVED_DATA}/Build/Products/Release/VoiceFlow.app"

case "${SIGNING_MODE}" in
  notarized)    DMG_SUFFIX="" ;;
  signed_only)  DMG_SUFFIX="-signed" ;;
  adhoc)        DMG_SUFFIX="-unsigned" ;;
esac
DMG_PATH="${DIST_DIR}/VoiceFlow-${VERSION}${DMG_SUFFIX}.dmg"

mkdir -p "${DIST_DIR}" "${BUILD_DIR}"
rm -rf "${STAGE_DIR}" "${DMG_PATH}"

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Sign
# -----------------------------------------------------------------------------

ENTITLEMENTS="Resources/VoiceFlow.entitlements"

if [[ "${SIGNING_MODE}" == "notarized" || "${SIGNING_MODE}" == "signed_only" ]]; then
  echo "==> Signing with Developer ID: ${DEVELOPER_ID}"
  # Deep sign with hardened runtime + timestamp (required for notarization).
  codesign --force --deep --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${DEVELOPER_ID}" \
    "${APP_PATH}"

  echo "==> Verifying signature"
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
else
  echo "==> Ad-hoc signing (local testing only)"
  codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS}" --sign - "${APP_PATH}"
fi

# -----------------------------------------------------------------------------
# Stage + DMG
# -----------------------------------------------------------------------------

echo "==> Creating DMG staging directory"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_PATH}" "${STAGE_DIR}/VoiceFlow.app"
ln -s /Applications "${STAGE_DIR}/Applications"

# Include first-run helper only for ad-hoc builds — signed/notarized users
# don't need it since Gatekeeper approves without quarantine stripping.
if [[ "${SIGNING_MODE}" == "adhoc" && -f "scripts/first_run.command" ]]; then
  cp "scripts/first_run.command" "${STAGE_DIR}/First Run (fix permissions).command"
  chmod +x "${STAGE_DIR}/First Run (fix permissions).command"
fi

echo "==> Creating DMG"
hdiutil create -volname "VoiceFlow" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}"

# -----------------------------------------------------------------------------
# Sign DMG (required for notarization)
# -----------------------------------------------------------------------------

if [[ "${SIGNING_MODE}" == "notarized" || "${SIGNING_MODE}" == "signed_only" ]]; then
  echo "==> Signing DMG"
  codesign --force --sign "${DEVELOPER_ID}" --timestamp "${DMG_PATH}"
fi

# -----------------------------------------------------------------------------
# Notarize + staple
# -----------------------------------------------------------------------------

if [[ "${SIGNING_MODE}" == "notarized" ]]; then
  echo "==> Submitting for notarization (this takes 1-5 minutes)"

  if [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "${DMG_PATH}" \
      --keychain-profile "${NOTARIZE_KEYCHAIN_PROFILE}" \
      --wait
  else
    xcrun notarytool submit "${DMG_PATH}" \
      --apple-id "${NOTARIZE_APPLE_ID}" \
      --team-id "${NOTARIZE_TEAM_ID}" \
      --password "${NOTARIZE_PASSWORD}" \
      --wait
  fi

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "${DMG_PATH}"

  echo "==> Verifying stapled notarization"
  xcrun stapler validate "${DMG_PATH}"
  spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}" || true
fi

# -----------------------------------------------------------------------------
# Checksum + summary
# -----------------------------------------------------------------------------

echo "==> Writing checksum"
shasum -a 256 "${DMG_PATH}" > "${DIST_DIR}/checksums.txt"

echo ""
echo "================================================================"
echo "  Build complete"
echo "  Mode:     ${SIGNING_MODE}"
echo "  DMG:      ${DMG_PATH}"
echo "  SHA-256:  $(cut -d' ' -f1 "${DIST_DIR}/checksums.txt")"
echo "================================================================"

case "${SIGNING_MODE}" in
  adhoc)
    echo "NOTE: Ad-hoc signed. End users will see Gatekeeper warnings."
    echo "      To ship to friends, use Homebrew Cask w/ the bundled first-run script."
    ;;
  signed_only)
    echo "NOTE: Signed but not notarized. Gatekeeper will still warn."
    echo "      Add NOTARIZE_* env vars to complete the chain."
    ;;
  notarized)
    echo "READY FOR DISTRIBUTION. End users can download and open directly."
    ;;
esac
