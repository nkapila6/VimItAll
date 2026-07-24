#!/bin/bash
set -e

cd "$(dirname "$0")"

VERSION="${1:-0.1.0}"
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/vimitall-apusiqelpkoogidcnhbsxlmcdfuz/Build/Products/Release/vimitall.app"
DMG_DIR="build/dmg"
DMG_PATH="build/vimitall-${VERSION}.dmg"

echo "==> Building release configuration"
xcodegen generate
xcodebuild -project vimitall.xcodeproj -scheme vimitall -configuration Release build \
	-derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/vimitall-apusiqelpkoogidcnhbsxlmcdfuz" \
	2>&1 | grep -E "error:|BUILD"

if [ ! -d "$APP_PATH" ]; then
	echo "ERROR: app not found at $APP_PATH"
	exit 1
fi

echo "==> Creating DMG"
rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "vimitall ${VERSION}" \
	-srcfolder "$DMG_DIR" \
	-ov -format UDZO \
	"$DMG_PATH"

echo "==> Signing DMG"
codesign -s - "$DMG_PATH"

echo "==> Done: $DMG_PATH"
echo "    To notarize: xcrun notarytool submit $DMG_PATH --keychain-profile vimitall --wait"
echo "    To staple:   xcrun stapler staple $DMG_PATH"
