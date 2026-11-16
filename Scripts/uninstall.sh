#!/bin/bash
set -euo pipefail

# One privileged step, run once as root, that undoes everything install.sh put in place: quit the app,
# unload the launchd job, delete the helper tool, its plist and the app copy, then clear the saved
# limit and the login-item entry for the signed-in user. Two entries, one copy of this file:
#
#     double-click "Uninstall Battery Charge Limit.app", which the DMG carries beside the app
#     sudo bash Scripts/uninstall.sh com.abneo.batterycharge.limit
#
# The app itself has no Uninstall entry.
#
# Unloading the job sends SIGTERM to the helper, and its signal handler writes the allow byte before it
# exits, so charging is back with macOS before anything on disk is touched. Closing the app's own XPC
# connection releases the same gate; quitting the app first is what covers a run where the app was
# still enforcing.

DEST_APP="/Applications/Battery Charge Limit.app"
HELPER_DIR="/Library/PrivilegedHelperTools"
APP_NAME="Battery Charge Limit"

if [[ $EUID -ne 0 ]]; then
    echo "uninstall.sh must run with administrator privileges" >&2
    exit 1
fi

# The uninstaller bundle passes the id from its own Swift copy of the identity. From a terminal, either
# name it or leave $DEST_APP in place so it can be read out of the installed Info.plist - the same
# rule install.sh follows.
APP_ID="${1:-}"
if [[ -z "$APP_ID" ]]; then
    APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST_APP/Contents/Info.plist" 2>/dev/null)"
fi
case "$APP_ID" in
    ""|*[!A-Za-z0-9.-]*)
        echo "usage: uninstall.sh [bundle id], or leave $DEST_APP in place so its id can be read" >&2
        exit 64
        ;;
esac
LABEL="$APP_ID.helper"
JOB_PLIST="/Library/LaunchDaemons/$LABEL.plist"
TOOL="$HELPER_DIR/$LABEL"

echo "== quitting $APP_NAME =="
pkill -f "$DEST_APP/Contents/MacOS/battery-charge-limit" 2>/dev/null || true

echo "== unloading system/$LABEL =="
launchctl bootout "system/$LABEL" 2>/dev/null || true
# bootout is asynchronous; if the helper is somehow still holding the mach name, ask it to exit
# politely rather than killing it, because the polite exit is the one that releases the charge gate.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$TOOL" >/dev/null 2>&1 || break
    sleep 0.5
done
if pgrep -f "$TOOL" >/dev/null 2>&1; then
    pkill -TERM -f "$TOOL" 2>/dev/null || true
    sleep 1
fi
launchctl print "system/$LABEL" >/dev/null 2>&1 && {
    echo "launchd still lists system/$LABEL" >&2
    exit 78
} || true

echo "== removing the helper, its job and $DEST_APP =="
rm -f "$JOB_PLIST" "$TOOL"
rm -rf "$DEST_APP"

# The settings and the login-item entry belong to the signed-in user, not to root, so they are
# removed in that user's own session. Console ownership is how the user is found: it is the same
# answer whether this script came from a terminal or from the app's password dialog.
CONSOLE_USER="$(stat -f%Su /dev/console)"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" ]]; then
    echo "no console user; clear the preferences and the login item by hand:"
    echo "  defaults delete $APP_ID"
    echo "  System Settings → General → Login Items & Extensions → $APP_NAME"
else
    uid="$(id -u "$CONSOLE_USER")"
    echo "== clearing $APP_ID preferences for $CONSOLE_USER =="
    launchctl asuser "$uid" sudo -H -u "$CONSOLE_USER" defaults delete "$APP_ID" 2>/dev/null ||
        echo "left the preferences alone; run: defaults delete $APP_ID"

    echo "== removing the login-item entry =="
    launchctl asuser "$uid" sudo -H -u "$CONSOLE_USER" osascript -e \
        "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null ||
        echo "left the login item alone; remove $APP_NAME under System Settings → General → Login Items & Extensions"
fi

echo "== done =="
for leftover in "$JOB_PLIST" "$TOOL" "$DEST_APP"; do
    if [[ -e "$leftover" ]]; then echo "still present: $leftover"; fi
done
if launchctl print "system/$LABEL" >/dev/null 2>&1; then echo "job still loaded: system/$LABEL"; fi
ioreg -rn AppleSmartBattery 2>/dev/null | grep -oE "\"(CurrentCapacity|IsCharging)\" = [^,]*" | head -2 || true
echo "charging is controlled by macOS again"
