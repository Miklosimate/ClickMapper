#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh --package
APP="$PWD/build/package/ClickMapper.app"
ARCH=$(uname -m)
mkdir -p dist
STAGING=$(mktemp -d "$PWD/build/installer.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
ditto "$APP" "$STAGING/ClickMapper.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Install.txt" <<'EOF'
ClickMapper 0.1.0 — macOS 14 or later

1. Quit any running ClickMapper instance using its menu bar panel.
2. Drag ClickMapper.app onto Applications.
3. Eject this disk image and open ClickMapper from Applications.
4. Grant Bluetooth and Accessibility access when requested.
5. If keyboard posting remains denied after granting Accessibility, fully
   quit ClickMapper from its menu bar panel and reopen the installed app.

ClickMapper appears as a keyboard icon in the menu bar. Open the mapper
there to configure buttons, connect your controllers, and enable output.

To launch at login, add /Applications/ClickMapper.app in System Settings
> General > Login Items & Extensions > Open at Login. Remove any previous
login item that points to the development build.

This local build is ad-hoc signed and is not notarized by Apple. Sharing it
with another Mac may trigger Gatekeeper. Public distribution requires a
Developer ID signing and notarization workflow.

Packaging does not reset permissions or modify an installed copy. The app
uses the same preferences identifier as the development build, preserving
saved mappings on this Mac. Avoid running both copies at the same time.
EOF
DMG="$PWD/dist/ClickMapper-0.1.0-$ARCH.dmg"
codesign --verify --deep --strict "$APP"
hdiutil create -volname ClickMapper -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
printf '%s\n' "$DMG"
