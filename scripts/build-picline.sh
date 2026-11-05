#!/bin/bash
# Build and package Picline for the current Mac (ad-hoc signing).
# Usage: scripts/build-picline.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;; esac
PREVIEW_DIR="$PWD/build"
PREVIEW_CACHE="${TMPDIR:-/private/tmp}/picline-build-cache"
OUTPUT_DIR="${PICLINE_OUTPUT_DIR:-$PREVIEW_DIR}"
APP="$OUTPUT_DIR/Picline.app"
# The version normally lives here, but a release build can override it so that
# CI derives the number from the tag instead of editing this file.
VERSION="${PICLINE_VERSION:-0.3.1}"
BUILD_NUMBER="${PICLINE_BUILD:-29}"
export CLANG_MODULE_CACHE_PATH="$PREVIEW_CACHE/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
# Release builds are universal so the app can be handed to Intel Macs too.
ARCH_ARGS=()
if [ "$CONFIGURATION" = release ]; then ARCH_ARGS=(--arch arm64 --arch x86_64); fi
# The cache flags are local conveniences; CI images do not always have the
# SwiftPM version that understands them, so CI asks for the plain form.
# ARCH_ARGS is empty for a debug build; bash 3.2 with `set -u` treats an empty
# array as unbound, hence the guard.
if [ "${PICLINE_SIMPLE:-0}" = 1 ]; then
  SWIFT_ARGS=(--disable-sandbox -c "$CONFIGURATION" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"})
else
  SWIFT_ARGS=(--disable-sandbox --scratch-path "$PREVIEW_DIR/swift-picline"
    --cache-path "$PREVIEW_CACHE/cache" --config-path "$PREVIEW_CACHE/config"
    --security-path "$PREVIEW_CACHE/security" -c "$CONFIGURATION" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"})
fi
swift build "${SWIFT_ARGS[@]}" --product Picline
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
# Start from a clean bundle so nothing from an older build lingers.
rm -rf "$APP/Contents"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Picline" "$APP/Contents/MacOS/.Picline.new"
mv -f "$APP/Contents/MacOS/.Picline.new" "$APP/Contents/MacOS/Picline"
for dir in Sources/Tendedero/Resources/*.lproj; do cp -R "$dir" "$APP/Contents/Resources/"; done
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/make-picline-icon.swift "$APP/Contents/Resources/Picline.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Picline</string>
  <key>CFBundleDisplayName</key><string>Picline</string>
  <key>CFBundleIdentifier</key><string>local.captureline.preview</string>
  <key>CFBundleExecutable</key><string>Picline</string>
  <key>CFBundleIconFile</key><string>Picline</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>es</string><string>fr</string><string>gl</string><string>az</string><string>hi</string><string>ja</string><string>ko</string><string>pt-BR</string><string>tr</string></array>
  <key>PiclineDefaultLanguage</key><string>zh-Hans</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>读取所选截图文件夹，将新截图挂到绳子上。</string>
  <key>NSDocumentsFolderUsageDescription</key><string>读取你选择的截图文件夹及其子文件夹。</string>
  <key>NSDownloadsFolderUsageDescription</key><string>读取你选择的截图文件夹及其子文件夹。</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key><string>挂到 Picline</string>
      </dict>
      <key>NSMessage</key><string>hangOnPicline</string>
      <key>NSPortName</key><string>Picline</string>
      <key>NSSendFileTypes</key>
      <array><string>public.image</string></array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Image</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.image</string></array>
    </dict>
  </array>
</dict></plist>
PLIST
# Keep the bundle identifier stable so existing preferences are retained.
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp NOTICE "$APP/Contents/Resources/NOTICE.txt"
codesign --force --sign - "$APP"
echo "Built $APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIR/Picline.zip"
echo "Packaged $OUTPUT_DIR/Picline.zip"
