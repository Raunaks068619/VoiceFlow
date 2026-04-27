#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# VoiceFlow — Build Verification Script
# ------------------------------------------------------------------------------
# Run this after every build (release_dmg.sh, release_dmg_unsigned.sh,
# build-and-install.sh) to confirm the build artifact won't ship broken.
#
# Usage:
#   scripts/verify_build.sh                    # checks /Applications/VoiceFlow.app
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

APP_RAW="${1:-/Applications/VoiceFlow.app}"
# Resolve to absolute path so defaults / codesign behave consistently.
if [[ -d "$APP_RAW" ]]; then
  APP="$(cd "$APP_RAW" && pwd)"
else
  APP="$APP_RAW"
fi
EXPECTED_BUNDLE_ID="com.voiceflow.app"
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

echo "⧞РVerifying: $APP"
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

# 3+4. Code signature + hardened runtime (capture once to avoid SIGPIPE under pipefail)
CS_OUTPUT="$(codesign -dv "$APP" 2>&1 || true)"

if echo "$CS_OUTPUT" | grep -q 'Signature='; then
  SIG_TYPE="$(echo "$CS_OUTPUT" | grep 'Signature=' | sed 's/.*Signature=//')"
  report ok "Code signature: $SIG_TYPE"
else
  report fail "No code signature"
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
echo "✕  Consider tccutil reset if iterating:"
echo "    tccutil reset Microphone $EXPECTED_BUNDLE_ID"

echo ""
if [[ "$FAILED" == "0" ]]; then
  echo "✅ All checks passed. Build is ship-safe."
  exit 0
else
  echo "❌ One or more checks failed. Do NOT ship this build."
  exit 1
fi
