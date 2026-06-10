#!/bin/bash
set -e

APP_NAME="OrbitMac"
SRC_DIR="/Users/shreyanshu/Desktop/term/OrbitMac"
BUILD_DIR="$SRC_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

echo "Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"

echo "Compiling Swift files..."
swiftc -o "$MACOS_DIR/$APP_NAME" "$SRC_DIR/OrbitMacApp.swift" "$SRC_DIR/DaemonManager.swift"

echo "Creating Info.plist..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.orbit.mac</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Done! App built at $APP_BUNDLE"
