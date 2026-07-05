#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ArelFocus"
BRIDGE_NAME="ArelFocusNativeBridge"
BUNDLE_ID="com.arel.focus"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Arel Focus.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/ArelFocus.icns"
BRIDGE_BINARY="$DIST_DIR/$BRIDGE_NAME"
CHROME_EXTENSION_ID="${AREL_FOCUS_EXTENSION_ID:-bahomlbhpbbbeffdgndnfbpmfnoemojc}"
CHROME_HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
CHROME_HOST_MANIFEST="$CHROME_HOST_DIR/com.arel.focus.bridge.json"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_DIR="$(swift build --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$DIST_DIR"
cp "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
cp "$BUILD_DIR/$BRIDGE_NAME" "$BRIDGE_BINARY"
cp "$APP_ICON" "$APP_RESOURCES/ArelFocus.icns"
chmod +x "$APP_BINARY" "$BRIDGE_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Arel Focus</string>
  <key>CFBundleIconFile</key>
  <string>ArelFocus.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Arel Focus may inspect app metadata for local time tracking.</string>
  <key>NSHumanReadableCopyright</key>
  <string>Local-first personal time tracking.</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

install_chrome_bridge() {
  mkdir -p "$CHROME_HOST_DIR"
  cat >"$CHROME_HOST_MANIFEST" <<JSON
{
  "name": "com.arel.focus.bridge",
  "description": "Arel Focus Chrome native messaging bridge",
  "path": "$BRIDGE_BINARY",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$CHROME_EXTENSION_ID/"
  ]
}
JSON
  echo "Installed Chrome native host: $CHROME_HOST_MANIFEST"
  echo "Native bridge: $BRIDGE_BINARY"
  echo "Extension ID: $CHROME_EXTENSION_ID"
}

case "$MODE" in
  run)
    open_app
    ;;
  --install-bridge|install-bridge)
    install_chrome_bridge
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "Arel Focus launched. Bundle: $APP_BUNDLE"
    echo "Native bridge: $BRIDGE_BINARY"
    echo "Chrome native host: $CHROME_HOST_MANIFEST"
    ;;
  *)
    echo "usage: $0 [run|--install-bridge|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
