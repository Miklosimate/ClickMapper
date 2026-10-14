#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/version.sh
./scripts/build-app.sh --package
APP="$PWD/build/package/ClickMapper.app"
ARCH=$(uname -m)
mkdir -p dist
STAGING=$(mktemp -d "$PWD/build/installer.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
ditto "$APP" "$STAGING/ClickMapper.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Install.txt" <<EOF
ClickMapper $CLICKMAPPER_VERSION — macOS 14 or later

1. Quit any running ClickMapper instance using its menu bar panel.
2. Drag ClickMapper.app onto Applications.
3. Eject this disk image and open ClickMapper from Applications.
4. Grant Bluetooth and Accessibility access when requested.
5. If keyboard posting remains denied after granting Accessibility, fully
   quit ClickMapper from its menu bar panel and reopen the installed app.

MACOS BLOCKS THE APP? REMOVE DOWNLOAD QUARANTINE

These builds are not notarized. If macOS refuses to open ClickMapper,
first copy it to Applications, then open Terminal and run:

xattr -dr com.apple.quarantine '/Applications/ClickMapper.app'
open '/Applications/ClickMapper.app'

Only do this for a download you trust from this repository's releases:
https://github.com/Miklosimate/ClickMapper/releases
This removes quarantine from ClickMapper and its bundled files. If you
installed it elsewhere, adjust both paths. Repeat after updates if needed.

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
DMG="$PWD/dist/ClickMapper-$CLICKMAPPER_VERSION-$ARCH.dmg"
codesign --verify --deep --strict "$APP"
hdiutil create -volname ClickMapper -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
printf '%s\n' "$DMG"
