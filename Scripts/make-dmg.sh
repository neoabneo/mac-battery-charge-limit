#!/bin/bash
set -euo pipefail

# Wraps the built bundles in a read-only disk image: the app, the uninstaller next to it and an
# Applications alias - the usual drag-to-install layout. Nothing in the image installs the helper; the
# first launch offers "Install helper", which runs Contents/Resources/install.sh through the
# administrator-password dialog.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Battery Charge Limit.app"
UNINSTALL_APP="$DIST/Uninstall Battery Charge Limit.app"
PLIST="$ROOT/Support/app-Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
DMG="$DIST/Battery Charge Limit ${VERSION}.dmg"
STAGE="$DIST/dmg-stage"

for bundle in "$APP" "$UNINSTALL_APP"; do
    if [[ ! -d "$bundle" ]]; then
        echo "no $bundle - run Scripts/build.sh first" >&2
        exit 66
    fi
done

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Battery Charge Limit.app"
ditto "$UNINSTALL_APP" "$STAGE/Uninstall Battery Charge Limit.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Battery Charge Limit" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

shasum -a 256 "$DMG"
echo "== built $DMG =="
