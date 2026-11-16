#!/bin/bash
set -euo pipefail

# Assembles and signs the two bundles the DMG carries. "Battery Charge Limit.app" is staged from the
# SwiftPM release build: the helper goes into Contents/Library/LaunchServices under its job label, and
# Scripts/install.sh is bundled at Contents/Resources as the one step that needs root.
# "Uninstall Battery Charge Limit.app" is the removal half, so the app never offers to delete itself;
# Scripts/uninstall.sh is bundled inside it instead. Ad-hoc signing is enough because the helper pins
# its client by cdhash rather than by a team anchor.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${BCL_SIGN_IDENTITY:--}"
DIST="$ROOT/dist"
APP="$DIST/Battery Charge Limit.app"
PLIST="$ROOT/Support/app-Info.plist"
UNINSTALL_APP="$DIST/Uninstall Battery Charge Limit.app"
UNINSTALL_PLIST="$ROOT/Support/uninstall-Info.plist"

# The bundle identifiers live only in the two plists. The helper is named after the app's, so build,
# installer and Swift all agree without carrying a second literal.
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
UNINSTALL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$UNINSTALL_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
HELPER_LABEL="$APP_ID.helper"

swift build -c release --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchServices" "$APP/Contents/Resources"

cp "$ROOT/.build/release/battery-charge-limit" "$APP/Contents/MacOS/battery-charge-limit"
cp "$ROOT/.build/release/bcl-helper" "$APP/Contents/Library/LaunchServices/$HELPER_LABEL"
cp "$PLIST" "$APP/Contents/Info.plist"
install -m 755 "$ROOT/Scripts/install.sh" "$APP/Contents/Resources/install.sh"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# macOS wants an .icns, not the SVG, so rasterize at the ten sizes iconutil expects and compile them.
# rsvg-convert is the only external tool this build needs. The two bundles get different glyphs: the
# app is the battery, the uninstaller is a bin, so the two cannot be mistaken for each other in the DMG.
slice() { rsvg-convert -f png -w "$1" -h "$1" -o "$2/$3" "$4"; }
iconset() {
    local set="$DIST/$(basename "$2" .icns).iconset"
    rm -rf "$set"
    mkdir -p "$set"
    slice 16   "$set" icon16x16.png      "$1"
    slice 32   "$set" icon16x16@2x.png   "$1"
    slice 32   "$set" icon32x32.png      "$1"
    slice 64   "$set" icon32x32@2x.png   "$1"
    slice 128  "$set" icon128x128.png    "$1"
    slice 256  "$set" icon128x128@2x.png "$1"
    slice 256  "$set" icon256x256.png    "$1"
    slice 512  "$set" icon256x256@2x.png "$1"
    slice 512  "$set" icon512x512.png    "$1"
    slice 1024 "$set" icon512x512@2x.png "$1"
    iconutil -c icns "$set" -o "$2"
    rm -rf "$set"
}
iconset "$ROOT/Support/icon.svg" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --identifier "$HELPER_LABEL" \
    "$APP/Contents/Library/LaunchServices/$HELPER_LABEL"
codesign --force --sign "$IDENTITY" --identifier "$APP_ID" "$APP"

rm -rf "$UNINSTALL_APP"
mkdir -p "$UNINSTALL_APP/Contents/MacOS" "$UNINSTALL_APP/Contents/Resources"
cp "$ROOT/.build/release/bcl-uninstaller" "$UNINSTALL_APP/Contents/MacOS/bcl-uninstaller"
cp "$UNINSTALL_PLIST" "$UNINSTALL_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$UNINSTALL_APP/Contents/Info.plist"
install -m 755 "$ROOT/Scripts/uninstall.sh" "$UNINSTALL_APP/Contents/Resources/uninstall.sh"
iconset "$ROOT/Support/icon-uninstall.svg" "$UNINSTALL_APP/Contents/Resources/UninstallIcon.icns"
printf 'APPL????' > "$UNINSTALL_APP/Contents/PkgInfo"
codesign --force --sign "$IDENTITY" --identifier "$UNINSTALL_ID" "$UNINSTALL_APP"

echo "== designated requirement install.sh will pin =="
codesign -d -r- "$APP" 2>&1 | sed -n 's/^# designated => //p'

echo "== signatures =="
codesign -dvv "$APP/Contents/Library/LaunchServices/$HELPER_LABEL" 2>&1 | sed -n '1,5p'
codesign -dvv "$APP" 2>&1 | sed -n '1,5p'
codesign -dvv "$UNINSTALL_APP" 2>&1 | sed -n '1,5p'

echo "== built $APP and $UNINSTALL_APP with identity: $IDENTITY =="
