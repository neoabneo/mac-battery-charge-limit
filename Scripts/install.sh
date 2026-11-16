#!/bin/bash
set -euo pipefail

# One privileged step, run once as root: put the app in /Applications, install the helper to
# /Library/PrivilegedHelperTools and register its launchd job. Either directly
#
#     sudo bash Scripts/install.sh "$(pwd)/dist/Battery Charge Limit.app"
#
# or from the app's own Install helper menu item, which passes its bundle path through the ordinary
# administrator-password dialog.
#
# SMJobBless is not used: it needs an Apple-anchored signing identity. Instead the job is registered
# here, and the helper is handed the designated requirement of the app copy installed right now, so it
# accepts exactly that cdhash. Rebuild the app and the pin has to be re-recorded by running this again.

SOURCE_APP="${1:-}"
DEST_APP="/Applications/Battery Charge Limit.app"
HELPER_DIR="/Library/PrivilegedHelperTools"

if [[ $EUID -ne 0 ]]; then
    echo "install.sh must run with administrator privileges" >&2
    exit 1
fi

if [[ -z "$SOURCE_APP" || ! -d "$SOURCE_APP" ]]; then
    echo "usage: install.sh <path to Battery Charge Limit.app>" >&2
    exit 64
fi

# Everything below is interpolated into a shell command and a plist without further quoting, so
# refuse anything that could break out of it.
case "$SOURCE_APP" in
    *[\'\"$\`\\]*)
        echo "app path contains a character the installer will not interpolate: $SOURCE_APP" >&2
        exit 64
        ;;
esac

# The identity is read out of the bundle being installed rather than written down again here, so the
# job label, the mach service name and the codesign identifier cannot drift from Scripts/build.sh.
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist" 2>/dev/null)"
LABEL="$APP_ID.helper"
JOB_PLIST="/Library/LaunchDaemons/$LABEL.plist"
case "$LABEL" in
    ""|*[!A-Za-z0-9.-]*)
        echo "no usable CFBundleIdentifier in $SOURCE_APP/Contents/Info.plist" >&2
        exit 66
        ;;
esac

if [[ ! -x "$SOURCE_APP/Contents/Library/LaunchServices/$LABEL" ]]; then
    echo "no helper staged in $SOURCE_APP/Contents/Library/LaunchServices - run Scripts/build.sh first" >&2
    exit 66
fi

echo "== staging $DEST_APP =="
if [[ -d "$DEST_APP" ]] &&
   [[ "$(stat -f '%d:%i' "$SOURCE_APP")" == "$(stat -f '%d:%i' "$DEST_APP")" ]]; then
    # The app that asked for the helper is itself the copy in /Applications. Deleting it first would
    # remove the bundle the user is looking at, and ditto then refuses to copy a bundle onto itself, so
    # this run would abort with the app gone and nothing installed. Keep the copy already there.
    echo "   already installed at $DEST_APP; keeping this copy"
else
    rm -rf "$DEST_APP"
    ditto "$SOURCE_APP" "$DEST_APP"
fi
chown -R root:wheel "$DEST_APP"
chmod 755 "$DEST_APP/Contents/MacOS/battery-charge-limit"

echo "== installing /Library/PrivilegedHelperTools/$LABEL =="
install -d -o root -g wheel -m 755 "$HELPER_DIR"
install -o root -g wheel -m 755 "$DEST_APP/Contents/Library/LaunchServices/$LABEL" "$HELPER_DIR/$LABEL"

codesign --verify "$DEST_APP"
codesign --verify "$HELPER_DIR/$LABEL"

DESIGNATED="$(codesign -d -r- "$DEST_APP" 2>&1 | sed -n 's/^# designated => //p' | head -1)"
DR_PATTERN='^cdhash H"[0-9a-fA-F]{40}"$'
if [[ ! "$DESIGNATED" =~ $DR_PATTERN ]]; then
    echo "could not read a usable designated requirement from $DEST_APP (got: $DESIGNATED)" >&2
    exit 65
fi
REQUIREMENT="$DESIGNATED and identifier \"$APP_ID\""

echo "== registering $JOB_PLIST =="
cat > "$JOB_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>MachServices</key>
	<dict>
		<key>$LABEL</key>
		<true/>
	</dict>
	<key>ProgramArguments</key>
	<array>
		<string>$HELPER_DIR/$LABEL</string>
		<string>--allow-requirement</string>
		<string>$REQUIREMENT</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
</dict>
</plist>
EOF
chown root:wheel "$JOB_PLIST"
chmod 644 "$JOB_PLIST"

launchctl bootout "system/$LABEL" 2>/dev/null || true
# bootout is asynchronous, and while the old helper still holds the mach name a bootstrap answers
# "Bootstrap failed: 5: Input/output error". So: wait for the old process to go, then retry bootstrap
# with a re-bootout between attempts until launchd takes the job.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$HELPER_DIR/$LABEL" >/dev/null 2>&1 || break
    sleep 0.5
done
bootstrap_error=""
for attempt in 1 2 3 4 5 6; do
    if bootstrap_error=$(launchctl bootstrap system "$JOB_PLIST" 2>&1); then
        break
    fi
    echo "bootstrap attempt $attempt failed: $bootstrap_error"
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    sleep "$attempt"
done
if ! launchctl print "system/$LABEL" >/dev/null 2>&1; then
    echo "launchd did not take the job: $bootstrap_error" >&2
    echo "run: sudo launchctl bootstrap system $JOB_PLIST" >&2
    exit 78
fi

echo "== helper accepts this client =="
echo "$REQUIREMENT"
echo "== job state =="
launchctl print "system/$LABEL" | grep -E "state = |pid = |path = " | head -5 || true
echo
echo "Installed. Remove it with the uninstaller bundle the DMG carries, or from a terminal:"
echo "  sudo bash Scripts/uninstall.sh $APP_ID"
