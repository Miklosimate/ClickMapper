#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/version.sh
PACKAGE_MODE=false
case "${1:-}" in
    "") ;;
    --package) PACKAGE_MODE=true ;;
    *) printf '%s\n' 'Usage: build-app.sh [--package]' >&2; exit 2 ;;
esac
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release
APP="$PWD/build/ClickMapper Diagnostic.app"
if "$PACKAGE_MODE"; then
    APP="$PWD/build/package/ClickMapper.app"
else
    /usr/bin/osascript -e 'if application id "local.clickmapper.diagnostic" is running then tell application id "local.clickmapper.diagnostic" to quit'
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClickDiagnostic "$APP/Contents/MacOS/ClickDiagnostic"
cp assets/ClickMapper.icns "$APP/Contents/Resources/ClickMapper.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClickDiagnostic</string>
<key>CFBundleIdentifier</key><string>local.clickmapper.diagnostic</string>
<key>CFBundleName</key><string>ClickMapper Diagnostic</string>
<key>CFBundleIconFile</key><string>ClickMapper.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Discover and test your Zwift Click controller button events.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CLICKMAPPER_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CLICKMAPPER_VERSION" "$APP/Contents/Info.plist"
if "$PACKAGE_MODE"; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName ClickMapper' "$APP/Contents/Info.plist"
fi
codesign --force --sign "${CLICKMAPPER_SIGN_IDENTITY:--}" "$APP"
if ! "$PACKAGE_MODE"; then
    sh scripts/reset-permission.sh
fi
printf '%s\n' "$APP"
