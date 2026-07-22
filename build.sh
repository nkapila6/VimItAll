#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/vimitall-apusiqelpkoogidcnhbsxlmcdfuz/Build/Products/Debug/vimitall.app"
BUNDLE_ID="app.vimitall.vimitall"

echo "==> Killing old vimitall"
pkill -f vimitall 2>/dev/null || true
sleep 1

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Building"
xcodebuild -project vimitall.xcodeproj -scheme vimitall -configuration Debug build \
	-derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/vimitall-apusiqelpkoogidcnhbsxlmcdfuz" \
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
