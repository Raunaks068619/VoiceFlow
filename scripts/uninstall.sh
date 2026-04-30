#!/usr/bin/env bash
set -uo pipefail

# -----------------------------------------------------------------------------
# VoiceFlow — Clean Uninstall
# -----------------------------------------------------------------------------
#
# Removes EVERYTHING VoiceFlow has placed on disk + wipes the macOS
# permission grants so the next install starts from a clean slate.
#
# What this nukes:
#   • The app bundle (/Applications/VoiceFlow.app — both Homebrew + manual)
#   • UserDefaults / preferences
#   • Application Support (run logs, magic words registry, audio files,
#     custom vocabulary, anything you ever dictated)
#   • Caches, logs, saved state, cookies, HTTPStorages
#   • TCC permission grants (Microphone, Accessibility, Input Monitoring)
#
# What it does NOT touch:
#   • Your OpenAI / Groq API keys stored OUTSIDE VoiceFlow (e.g. env vars)
#   • The Homebrew tap itself (you can re-install with the same command)
#   • Anything in /Library (system-wide install — VoiceFlow doesn't use it)
#
# Usage:
#   ./scripts/uninstall.sh              # interactive (asks before deleting)
#   ./scripts/uninstall.sh --force      # skip confirmation
#
# After running, restart Mac (recommended — TCC sometimes caches grants
# in memory) and re-install via:
#   brew install --cask raunaks068619/voiceflow/voiceflow
# -----------------------------------------------------------------------------

BUNDLE_ID="com.voiceflow.app"
APP_NAME="VoiceFlow"
APP_PATH="/Applications/${APP_NAME}.app"
FORCE="${1:-}"

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold()  { printf "\033[1m%s\033[0m\n" "$*"; }

bold "🧹  VoiceFlow uninstall"
echo "    Bundle ID: ${BUNDLE_ID}"
echo "    App path:  ${APP_PATH}"
echo

# Confirm unless --force.
if [[ "${FORCE}" != "--force" ]]; then
    yellow "This will DELETE every trace of VoiceFlow:"
    echo "  • The app itself"
    echo "  • Run log (recordings, transcripts, prompts)"
    echo "  • Saved API keys, magic words, custom vocabulary, settings"
    echo "  • All Library/Caches/Logs/Preferences entries"
    echo "  • macOS permission grants (Microphone, Accessibility, Input Monitoring)"
    echo
    read -p "Type 'yes' to continue: " confirm
    if [[ "${confirm}" != "yes" ]]; then
        red "✗ Aborted. Nothing was deleted."
        exit 1
    fi
fi

# 1. Kill any running instance — file deletion will fail otherwise on a
#    process that's holding handles open. `|| true` because pkill returns
#    non-zero when no process matched, which is fine here.
echo
bold "==> 1/5  Stopping VoiceFlow..."
pkill -f "${APP_NAME}.app" 2>/dev/null || true
sleep 1

# 2. Remove the app. Try the Homebrew uninstall path first (cleanly removes
#    the cask record); fall back to direct removal for manual installs.
bold "==> 2/5  Removing app bundle..."
if command -v brew >/dev/null 2>&1; then
    if brew list --cask voiceflow >/dev/null 2>&1; then
        brew uninstall --cask voiceflow 2>/dev/null || true
        green "    ✓ Removed via Homebrew"
    fi
fi
if [[ -d "${APP_PATH}" ]]; then
    # The app may need elevated rm if it was installed root-owned.
    if ! rm -rf "${APP_PATH}" 2>/dev/null; then
        yellow "    ! Need admin password to remove root-owned app"
        sudo rm -rf "${APP_PATH}"
    fi
    green "    ✓ Removed ${APP_PATH}"
fi

# 3. Wipe all user-scope Library entries. Each line is independent — we
#    use `2>/dev/null || true` so a missing path doesn't abort the run.
bold "==> 3/5  Wiping Library entries..."
LIB="${HOME}/Library"
PATHS=(
    "${LIB}/Application Support/${APP_NAME}"
    "${LIB}/Caches/${BUNDLE_ID}"
    "${LIB}/Caches/${BUNDLE_ID}.ShipIt"
    "${LIB}/Containers/${BUNDLE_ID}"
    "${LIB}/Group Containers/${BUNDLE_ID}"
    "${LIB}/Cookies/${BUNDLE_ID}.binarycookies"
    "${LIB}/HTTPStorages/${BUNDLE_ID}"
    "${LIB}/HTTPStorages/${BUNDLE_ID}.binarycookies"
    "${LIB}/LaunchAgents/${BUNDLE_ID}.plist"
    "${LIB}/Logs/${APP_NAME}"
    "${LIB}/Preferences/${BUNDLE_ID}.plist"
    "${LIB}/Preferences/ByHost/${BUNDLE_ID}.*.plist"
    "${LIB}/Saved Application State/${BUNDLE_ID}.savedState"
    "${LIB}/WebKit/${BUNDLE_ID}"
)
for p in "${PATHS[@]}"; do
    # Globs need shell expansion; quote-protect the literal path otherwise.
    if [[ "${p}" == *"*"* ]]; then
        rm -rf ${p} 2>/dev/null || true
    else
        rm -rf "${p}" 2>/dev/null || true
    fi
done

# Crash reports are filename-globbed, not bundle-id'd.
rm -f "${LIB}/Logs/DiagnosticReports/${APP_NAME}"_*.{crash,ips} 2>/dev/null || true
rm -f "${LIB}/Logs/CrashReporter/${APP_NAME}"_*.crash 2>/dev/null || true
green "    ✓ Library wiped"

# 4. Reset TCC permissions. Each service is independent — a failure on
#    one (e.g. macOS version doesn't recognize a service name) doesn't
#    abort the others.
bold "==> 4/5  Resetting macOS permissions (TCC)..."
TCC_SERVICES=(
    "Microphone"          # 🎤
    "Accessibility"       # ♿
    "ListenEvent"         # ⌨️  Input Monitoring (modern name)
    "PostEvent"           # ⌨️  Input Monitoring (legacy fallback)
    "SystemPolicyAllFiles"
)
for svc in "${TCC_SERVICES[@]}"; do
    tccutil reset "${svc}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
done
green "    ✓ TCC grants reset"

# 5. Clear UserDefaults via cfprefsd domain — belt-and-suspenders. Even
#    after deleting the .plist file, cfprefsd may have cached values in
#    memory until the next reboot. `defaults delete` flushes that cache.
bold "==> 5/5  Flushing UserDefaults cache..."
defaults delete "${BUNDLE_ID}" >/dev/null 2>&1 || true
killall cfprefsd 2>/dev/null || true
green "    ✓ UserDefaults flushed"

echo
green "✅ VoiceFlow fully removed."
echo
yellow "Recommended:"
echo "  1. Restart your Mac (TCC sometimes holds permission grants in"
echo "     memory until logout). Skip this if you've never granted"
echo "     VoiceFlow any permissions before."
echo "  2. Re-install:"
echo "       brew install --cask raunaks068619/voiceflow/voiceflow"
