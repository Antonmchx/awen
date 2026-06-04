#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="/private/tmp/sketchbook-build"
BUILD_DIR="$BUILD_ROOT/arm64-apple-macosx/debug"
APP_NAME="awen"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

HOME=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache \
swift build --scratch-path "$BUILD_ROOT" --package-path "$ROOT_DIR"

cp "$BUILD_DIR/SketchBookPlayer" "$MACOS_DIR/$APP_NAME"
cp -R "$BUILD_DIR/SketchBookPlayer_SketchBookPlayer.bundle" "$RESOURCES_DIR/"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>awen</string>
    <key>CFBundleIdentifier</key>
    <string>local.awen.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>awen</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_NAME"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
