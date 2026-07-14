#!/bin/bash
# Build Mascot.app - a real macOS application bundle
# Output: build/Mascot.app
# Usage:  ./build.sh            build only
#         ./build.sh --install  build, then replace /Applications/Mascot.app and relaunch

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Mascot"
BUILD_DIR="$DIR/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $APP_NAME.app..."

# Clean and recreate the bundle skeleton
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

# 1. Compile the swift source into a universal (arm64 + x86_64) binary
echo "  -> compiling binary (universal)"
swiftc -O -target arm64-apple-macos12.0 \
  -o "$BUILD_DIR/$APP_NAME-arm64" "$DIR/MascotApp.swift"
swiftc -O -target x86_64-apple-macos12.0 \
  -o "$BUILD_DIR/$APP_NAME-x86_64" "$DIR/MascotApp.swift"
lipo -create -output "$MACOS/$APP_NAME" \
  "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"
rm "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"

# 2. Copy mascot.html into Resources
echo "  -> copying mascot.html"
cp "$DIR/mascot.html" "$RESOURCES/mascot.html"

# 3. Generate the .icns icon
echo "  -> generating icon"
swift "$DIR/build-icon.swift" "$BUILD_DIR" >/dev/null
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$RESOURCES/AppIcon.icns"
rm -rf "$BUILD_DIR/AppIcon.iconset"

# 4. Write Info.plist (LSUIElement: menu-bar app, no Dock icon)
echo "  -> writing Info.plist"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Mascot</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Code Mascot</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.maulmota.mascot</string>
    <key>CFBundleVersion</key>
    <string>2.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.1.0</string>
    <key>CFBundleExecutable</key>
    <string>Mascot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# 5. Ad-hoc codesign so Gatekeeper trusts a locally-built app
echo "  -> ad-hoc signing"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo ""
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  echo ""
  echo "Installing to /Applications..."
  killall Mascot 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "Installed and launched /Applications/$APP_NAME.app"
else
  echo ""
  echo "Install with:  ./build.sh --install"
  echo "Or drag build/$APP_NAME.app to /Applications in Finder."
fi
