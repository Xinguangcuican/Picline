#!/bin/bash
# Builds Picline.app and packs it into a disk image that can be handed out.
# Keeps Finder scripting out of the way: no window layout, no prompts.
# Usage: scripts/package-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Skip the rebuild when the caller has just built the app (CI does this).
if [ "${PICLINE_SKIP_BUILD:-0}" != 1 ]; then
  scripts/build-picline.sh release
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Picline.app/Contents/Info.plist)"
DMG="build/Picline-$VERSION.dmg"
README="${README_PATH:-安装说明.txt}"
[ -f "$README" ] || README="../dist/安装说明.txt"

WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
cp -R build/Picline.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
[ -f "$README" ] && cp "$README" "$STAGE/"

rm -f "$DMG"
hdiutil create -quiet -srcfolder "$STAGE" -volname "Picline $VERSION" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
rm -rf "$WORK"
echo "Built $DMG"
