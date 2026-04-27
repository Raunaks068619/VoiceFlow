#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# VoiceFlow — First Run Helper
# ------------------------------------------------------------------------------
# Double-click this file ONCE after dragging VoiceFlow.app to /Applications.
#
# What it does:
#   1. Strips Gatekeeper quarantine flag (so unsigned/adhoc app can launch)
#   2. Resets any stale TCC entries from prior installs
#   3. Launches VoiceFlow
#
# What it DOES NOT do:
#   - Does NOT re-sign the app. The DMG-shipped app is already signed
#     adhoc with the correct entitlements (mic, accessibility, etc).
#     Re-signing here would STRIP entitlements and break permissions.
# -----------------------------------------------------------------------------

set -euo pipefail

APP="/Applications/VoiceFlow.app"
BUNDLE_ID="com.voiceflow.app"

if [[ ! -d "$APP" ]]; then
  echo "❌ VoiceFlow.app not found at $APP"
  echo "   Drag VoiceFlow.app into Applications first, then run this again."
  echo ""
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

echo "==> Quitting any running VoiceFlow instance"
pkill -x VoiceFlow 2>/dev/null || true
sleep 1

echo "==> Stripping Gatekeeper quarantine flag"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true

echo "==> Verifying entitlements survived (sanity check)"
if codesign -d --entitlements - "$APP" 2>&1 | grep -q audio-input; then
  echo "   ✅ audio-input entitlement present"
else
  echo "   ⚠️  audio-input entitlement MISSING — please report this build"
fi

echo "==> Resetting any stale TCC permission state"
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
tccutil reset SpeechRecognition "$BUNDLE_ID" 2>/dev/null || true

echo ""
echo "✅ Setup complete. Launching VoiceFlow..."
open "$APP"

echo ""
echo "When the menu-bar icon appears, grant the requested permissions in onboarding."
echo ""
read -n 1 -s -r -p "Press any key to close this window..."
