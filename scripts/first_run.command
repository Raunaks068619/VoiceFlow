#!/usr/bin/env bash
# Double-click this file after installing VoiceFlow to /Applications.
# It strips Gatekeeper quarantine and re-applies a local ad-hoc signature so
# microphone / accessibility / input-monitoring permissions persist.

set -euo pipefail

APP="/Applications/VoiceFlow.app"

if [[ ! -d "$APP" ]]; then
  echo "❌ VoiceFlow.app not found at $APP"
  echo "   Drag VoiceFlow.app to /Applications first, then run this again."
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

echo "==> Stripping quarantine flag"
xattr -dr com.apple.quarantine "$APP" || true

echo "==> Re-signing locally (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Resetting TCC entries (optional, safe)"
tccutil reset Microphone com.voiceflow.app 2>/dev/null || true
tccutil reset Accessibility com.voiceflow.app 2>/dev/null || true
tccutil reset ListenEvent com.voiceflow.app 2>/dev/null || true

echo ""
echo "✅ Done. Launching VoiceFlow..."
open "$APP"

echo ""
echo "When the menu-bar icon appears, grant the 3 permissions in onboarding."
read -n 1 -s -r -p "Press any key to close this window..."
