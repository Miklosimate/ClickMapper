#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release
APP="$PWD/build/ClickMapper Diagnostic.app"
/usr/bin/osascript -e 'if application id "local.clickmapper.diagnostic" is running then tell application id "local.clickmapper.diagnostic" to quit'
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClickDiagnostic "$APP/Contents/MacOS/ClickDiagnostic"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClickDiagnostic</string>
<key>CFBundleIdentifier</key><string>local.clickmapper.diagnostic</string>
<key>CFBundleName</key><string>ClickMapper Diagnostic</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Discover and test your Zwift Click controller button events.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
sh scripts/reset-permission.sh
printf '%s\n' "$APP"
