#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/DerivedData"
APP_NAME="VoiceFlow"
INSTALL_DIR="/Applications"

echo "Building $APP_NAME (Release)..."
xcodebuild \
  -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build 2>&1 | tail -20

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "ERROR: Build product not found at $BUILT_APP"
  exit 1
fi

echo "Killing running $APP_NAME..."
pkill -f "$APP_NAME.app" 2>/dev/null || true
sleep 1

echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$BUILT_APP" "$INSTALL_DIR/$APP_NAME.app"

echo "Launching..."
open "$INSTALL_DIR/$APP_NAME.app"

echo "Done! $APP_NAME is running."
