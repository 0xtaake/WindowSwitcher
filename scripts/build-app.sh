#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WindowSwitcher"
APP_VERSION="0.3.8"
BUILD_NUMBER="13"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/release/$APP_NAME"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
MASTER_ICON="$ROOT_DIR/.build/AppIcon-1024.png"

cd "$ROOT_DIR"
swift build -c release

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Build fehlgeschlagen: ausführbare Datei nicht gefunden: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Generate an .icns file from the same SF Symbol used in the menu bar.
# All work happens in the user's project directory; no admin privileges are needed.
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$MASTER_ICON"

make_icon_size() {
  local filename="$1"
  local pixels="$2"
  sips -z "$pixels" "$pixels" "$MASTER_ICON" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon_size "icon_16x16.png" 16
make_icon_size "icon_16x16@2x.png" 32
make_icon_size "icon_32x32.png" 32
make_icon_size "icon_32x32@2x.png" 64
make_icon_size "icon_128x128.png" 128
make_icon_size "icon_128x128@2x.png" 256
make_icon_size "icon_256x256.png" 256
make_icon_size "icon_256x256@2x.png" 512
make_icon_size "icon_512x512.png" 512
make_icon_size "icon_512x512@2x.png" 1024

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>de.local.windowswitcher</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
codesign --force --deep --sign - "$APP_DIR"

echo "App erstellt: $APP_DIR"
echo "App-Icon: $APP_DIR/Contents/Resources/AppIcon.icns"
echo "Starten mit: open \"$APP_DIR\""
