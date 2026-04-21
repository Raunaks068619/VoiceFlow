#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# VoiceFlow Ship Script
# -----------------------------------------------------------------------------
#
# Thin wrapper that sources .env.signing and runs release_dmg.sh.
#
# Usage:
#   ./scripts/ship.sh v0.3.0
#
# Before first use:
#   1. cp .env.signing.example .env.signing
#   2. Fill in the real values (see scripts/README_SIGNING.md)
#   3. Make sure the Developer ID cert is in your Keychain
#
# Behavior:
#   - With creds in .env.signing → produces a signed + notarized DMG
#   - Without .env.signing       → falls back to ad-hoc signed DMG (warns)
# -----------------------------------------------------------------------------

VERSION="${1:-}"

if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 <version>   e.g. $0 v0.3.0"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE=".env.signing"

if [[ -f "${ENV_FILE}" ]]; then
  echo "==> Loading credentials from ${ENV_FILE}"
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "==> ${ENV_FILE} not found — falling back to ad-hoc signing."
  echo "    (copy .env.signing.example → .env.signing and fill in real values"
  echo "     for a signed + notarized build.)"
fi

echo "==> Running release build"
./scripts/release_dmg.sh --version "${VERSION}"

# -----------------------------------------------------------------------------
# Post-build — copy to the stable filename expected by the Homebrew cask,
# and print a one-line summary with the SHA the cask needs.
# -----------------------------------------------------------------------------

# release_dmg.sh writes different filenames based on signing mode:
#   notarized     → dist/VoiceFlow-<VERSION>.dmg
#   signed_only   → dist/VoiceFlow-<VERSION>-signed.dmg
#   adhoc         → dist/VoiceFlow-<VERSION>-unsigned.dmg
# Whichever one exists, copy it to the stable cask filename.
SOURCE_DMG=""
for suffix in "" "-signed" "-unsigned"; do
  candidate="dist/VoiceFlow-${VERSION}${suffix}.dmg"
  if [[ -f "${candidate}" ]]; then
    SOURCE_DMG="${candidate}"
    break
  fi
done

if [[ -z "${SOURCE_DMG}" ]]; then
  echo "ERROR: could not locate built DMG under dist/"
  exit 1
fi

STABLE_DMG="dist/VoiceFlow-Beta.dmg"
cp "${SOURCE_DMG}" "${STABLE_DMG}"
SHA=$(shasum -a 256 "${STABLE_DMG}" | cut -d' ' -f1)

cat <<EOF

================================================================
  Ready to release
  Source DMG:  ${SOURCE_DMG}
  Cask DMG:    ${STABLE_DMG}
  SHA-256:     ${SHA}

  Next steps:
    1. Update homebrew-voiceflow/Casks/voiceflow.rb:
         version "${VERSION#v}"
         sha256  "${SHA}"

    2. Cut the GitHub release:
         gh release create ${VERSION} ${STABLE_DMG} \\
           --title "${VERSION}" --notes "Release notes here"

    3. Push the tap:
         (cd homebrew-voiceflow && git add -A && \\
          git commit -m "voiceflow ${VERSION#v}" && git push)
================================================================
EOF
