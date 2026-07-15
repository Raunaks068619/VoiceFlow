#!/bin/bash
# pipefail is critical: without it, `xcodebuild ... | tail` hides a failed
# build behind tail's exit 0, and the script installs whatever stale .app is
# already on disk. That silently shipped an old binary before.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/DerivedData"
PROJECT_NAME="Vordi"
APP_NAME="Vordi"
APP_DISPLAY_NAME="Vordi"
INSTALL_DIR="/Applications"

BUILD_LOG="$(mktemp)"

run_xcodebuild() {
  if ! xcodebuild \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build > "$BUILD_LOG" 2>&1; then
    echo "ERROR: Release build FAILED — not installing (last 25 lines):"
    tail -25 "$BUILD_LOG"
    exit 1
  fi
}

# Deterministic freshness check: the object file for a recently-added source
# must exist in THIS build's intermediates. `strings` on the linked binary is
# unreliable (it silently misses some literals), so we check the .o instead.
# Bump this filename when adding a source you want to guarantee ships.
MARKER_OBJ="AgentConnectView.o"
marker_compiled() {
  find "$BUILD_DIR/Build/Intermediates.noindex" -name "$MARKER_OBJ" 2>/dev/null | grep -q .
}

echo "Building $APP_DISPLAY_NAME (Release)..."
run_xcodebuild

# Hand-edited pbxproj + stale DerivedData => new files silently not compiled.
# Self-heal: if the marker didn't compile, wipe DerivedData and rebuild once.
if ! marker_compiled; then
  echo "  ⚠️  new sources not picked up (stale DerivedData) — clean rebuild..."
  rm -rf "$BUILD_DIR"
  run_xcodebuild
fi
if ! marker_compiled; then
  echo "ERROR: '$MARKER_OBJ' never compiled even after a clean build."
  echo "       Check that it's registered in $PROJECT_NAME.xcodeproj (PBXBuildFile + Sources phase)."
  exit 1
fi
echo "  ✓ latest sources compiled ($MARKER_OBJ)"

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "ERROR: Build product not found at $BUILT_APP"
  exit 1
fi

echo "Building vordi-mcp (Release)..."
( cd "$PROJECT_DIR/vordi-mcp" && swift build -c release 2>&1 | tail -5 )
MCP_BIN="$PROJECT_DIR/vordi-mcp/.build/release/vordi-mcp"
if [ ! -f "$MCP_BIN" ]; then
  echo "ERROR: vordi-mcp binary not found at $MCP_BIN"
  exit 1
fi

echo "Bundling vordi-mcp into app (Contents/MacOS/)..."
cp "$MCP_BIN" "$BUILT_APP/Contents/MacOS/vordi-mcp"

echo "Killing running $APP_DISPLAY_NAME..."
pkill -f "$APP_NAME.app" 2>/dev/null || true
sleep 1

echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$BUILT_APP" "$INSTALL_DIR/$APP_NAME.app"

# Sign the bundled helper explicitly first (--deep is deprecated/unreliable for
# nested Mach-O helpers), then the app, so the outer signature stays valid.
echo "Signing bundled vordi-mcp..."
codesign --force --options runtime \
  --sign - "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/vordi-mcp"

echo "Signing installed app with local entitlements..."
codesign --force --deep --options runtime \
  --entitlements "$PROJECT_DIR/Resources/Vordi.entitlements" \
  --sign - "$INSTALL_DIR/$APP_NAME.app"

echo "Verifying bundled vordi-mcp responds over stdio..."
BUNDLED_MCP="$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/vordi-mcp"
MCP_CHECK=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  | "$BUNDLED_MCP" 2>/dev/null | head -1)
if echo "$MCP_CHECK" | grep -q '"serverInfo"'; then
  echo "  ✓ bundled vordi-mcp is live"
else
  echo "  ⚠️  bundled vordi-mcp did not respond — check signing/quarantine"
fi

echo "Launching..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "Done! $APP_DISPLAY_NAME is running."
echo "Connect an agent (Claude Code):"
echo "  claude mcp add vordi -- \"$BUNDLED_MCP\""
