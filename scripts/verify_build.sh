#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Vordi — Build Verification Script
# ------------------------------------------------------------------------------
# Run this after every build (release_dmg.sh, release_dmg_unsigned.sh,
# build-and-install.sh) to confirm the build artifact won't ship broken.
#
# Usage:
#   scripts/verify_build.sh                    # checks /Applications/Vordi.app
#   scripts/verify_build.sh path/to/app        # checks custom path
#
# Fails loudly if:
#   - Bundle ID wrong
#   - NSMicrophoneUsageDescription missing from Info.plist
#   - audio-input entitlement not embedded in signature
#   - Hardened runtime flag not set
#   - No valid code signature
# ------------------------------------------------------------------------------

set -euo pipefail

APP_RAW="${1:-/Applications/Vordi.app}"
# Resolve to absolute path so defaults / codesign behave consistently.
if [[ -d "$APP_RAW" ]]; then
  APP="$(cd "$APP_RAW" && pwd)"
else
  APP="$APP_RAW"
fi
EXPECTED_BUNDLE_ID="com.vordi.app"
FAILED=0

if [[ ! -d "$APP" ]]; then
  echo "❌ App bundle not found: $APP"
  exit 2
fi

report() {
  local status="$1" msg="$2"
  if [[ "$status" == "ok" ]]; then
    echo "✅ $msg"
  else
    echo "❌ $msg"
    FAILED=1
  fi
}

echo "🔍 Verifying: $APP"
echo ""

# 1. Bundle ID
ACTUAL_BUNDLE_ID=$(defaults read "$APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "MISSING")
if [[ "$ACTUAL_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]]; then
  report ok "Bundle ID: $ACTUAL_BUNDLE_ID"
else
  report fail "Bundle ID mismatch: got $ACTUAL_BUNDLE_ID, want $EXPECTED_BUNDLE_ID"
fi

# 2. Info.plist permission strings
for key in NSMicrophoneUsageDescription; do
  if plutil -p "$APP/Contents/Info.plist" | grep -q "$key"; then
    report ok "Key in Info.plist: $key"
  else
    report fail "Missing Info.plist key: $key"
  fi
done

# 3+4. Code signature + hardened runtime. Modern codesign output does not
# consistently include a Signature= line, so verify the signature directly.
CS_OUTPUT="$(codesign -dv --verbose=4 "$APP" 2>&1 || true)"

if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  SIGNING_AUTHORITY="$(echo "$CS_OUTPUT" | sed -n 's/^Authority=//p' | head -1)"
  report ok "Code signature: ${SIGNING_AUTHORITY:-valid}"
else
  report fail "Invalid or missing code signature"
fi

FLAGS="$(echo "$CS_OUTPUT" | grep -E '^CodeDirectory' | grep -oE 'flags=0x[0-9a-f]+\([^)]*\)' || true)"
if echo "$FLAGS" | grep -q runtime; then
  report ok "Hardened runtime enabled ($FLAGS)"
else
  report fail "Hardened runtime not enabled ($FLAGS)"
fi

# 5. entitlements embedded
ENT=$(codesign -d --entitlements - "$APP" 2>/dev/null || echo "")
for req in "com.apple.security.device.audio-input"; do
  if echo "$ENT" | grep -q "$req"; then
    report ok "Entitlement present: $req"
  else
    report fail "Entitlement MISSING: $req"
  fi
done

# 6. TCC state (informational)
echo ""
echo "ℹ️  Consider tccutil reset if iterating:"
echo "    tccutil reset Microphone $EXPECTED_BUNDLE_ID"

echo ""
if [[ "$FAILED" == "0" ]]; then
  echo "✅ All checks passed. Build is ship-safe."
  exit 0
else
  echo "❌ One or more checks failed. Do NOT ship this build."
  exit 1
fi
