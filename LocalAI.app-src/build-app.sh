#!/bin/bash
# build-app.sh — Sokora.app バンドルを作成する
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$SCRIPT_DIR/Sokora.app"

echo "🔨 Building Sokora (release)..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

echo "📦 Creating Sokora.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# バイナリをコピー
cp "$BUILD_DIR/Sokora" "$APP_DIR/Contents/MacOS/Sokora"
chmod +x "$APP_DIR/Contents/MacOS/Sokora"

# Info.plist 生成
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.enablerdao.sokora</string>
    <key>CFBundleName</key>
    <string>Sokora</string>
    <key>CFBundleDisplayName</key>
    <string>Sokora</string>
    <key>CFBundleExecutable</key>
    <string>Sokora</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Enabler DAO. MIT License.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo ""
echo "✅ Sokora.app を作成しました: $APP_DIR"
echo ""
echo "インストール方法:"
echo "  cp -R Sokora.app /Applications/"
echo "  open /Applications/Sokora.app"
echo ""
echo "または直接起動:"
echo "  open $APP_DIR"
