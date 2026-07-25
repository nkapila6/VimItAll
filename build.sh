#!/bin/bash
set -e

cd "$(dirname "$0")"

DERIVED_DATA_PATH="./build/derived"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/vimitall.app"
BUNDLE_ID="app.vimitall.vimitall"

echo "==> Killing old vimitall"
pkill -f vimitall 2>/dev/null || true
sleep 1

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Building"
xcodebuild -project vimitall.xcodeproj -scheme vimitall -configuration Debug build \
	-derivedDataPath "$DERIVED_DATA_PATH" \
	2>&1 | grep -E "error:|BUILD"

echo "==> Resetting Accessibility permission"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo "==> Launching"
open "$APP_PATH"
sleep 2

if pgrep -f vimitall >/dev/null; then
	echo "==> vimitall is running (PID $(pgrep -f vimitall | head -1))"
	echo "==> Grant Accessibility permission in System Settings > Privacy & Security"
	echo "    The app will auto-start once you toggle it on."
else
	echo "==> ERROR: vimitall did not start"
fi
