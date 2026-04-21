#!/bin/bash
# bump_cask.sh — rebuild DMG, update cask version + sha256, print next steps
# Usage:  ./bump_cask.sh 0.1.0-beta.2
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.1.0-beta.2"
    exit 1
fi

VERSION=$1
VF_ROOT=/Users/raunaksingh/Documents/VoiceFlow
DMG="$VF_ROOT/VoiceFlow-Beta.dmg"
CASK="$VF_ROOT/homebrew-voiceflow/Casks/voiceflow.rb"
BUILD_SCRIPT="$VF_ROOT/build_beta_dmg.sh"

echo "=== 1/4  Rebuild DMG ==="
if [ ! -x "$BUILD_SCRIPT" ]; then
    # Script might not be executable; run via bash explicitly
    bash "$BUILD_SCRIPT"
else
    "$BUILD_SCRIPT"
fi

echo
echo "=== 2/4  Compute SHA-256 ==="
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "sha256: $SHA"

echo
echo "=== 3/4  Update cask file ==="
# BSD sed (macOS) needs empty -i argument
sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK"
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" "$CASK"
echo "Updated $CASK"
grep -E 'version|sha256' "$CASK" | head -2

echo
echo "=== 4/4  Next steps (run these manually) ==="
cat <<EONEXT

  # 1. Cut the DMG release on the voiceflow (source) repo:
  cd "$VF_ROOT"
  gh release create "v$VERSION" "$DMG" \\
    --repo raunaksingh/voiceflow \\
    --title "VoiceFlow $VERSION" \\
    --notes "Beta release. Install: brew install --cask raunaksingh/voiceflow/voiceflow"

  # 2. Commit + push the cask bump to the tap repo:
  cd "$VF_ROOT/homebrew-voiceflow"
  git add Casks/voiceflow.rb
  git commit -m "voiceflow $VERSION"
  git push

  # 3. Test locally before announcing:
  brew install --cask --debug raunaksingh/voiceflow/voiceflow

EONEXT
