#!/bin/sh
# Builds OpenPaste.app (an .app bundle is required for the menu bar agent and the Accessibility permission).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=OpenPaste.app
VERSION=${VERSION#v}  # tag "v1.2.0" -> "1.2.0"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/OpenPaste "$APP/Contents/MacOS/"
cp icon/AppIcon.icns "$APP/Contents/Resources/"  # regenerate with: swift icon/make-icon.swift
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>OpenPaste</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.openpaste.app</string>
  <key>CFBundleName</key><string>OpenPaste</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-0.1}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
# A stable certificate keeps the Accessibility permission across rebuilds; ad-hoc ("-") changes every build.
# Override with SIGN_IDENTITY=...; falls back to ad-hoc when no certificate exists (e.g. CI).
IDS=$(security find-identity -v -p codesigning)
DEVELOPER_ID=$(echo "$IDS" | awk -F'"' '/Developer ID Application/ {print $2; exit}')
DEVELOPMENT=$(echo "$IDS" | awk -F'"' '/Apple Development/ {print $2; exit}')
IDENTITY=${SIGN_IDENTITY:-${DEVELOPER_ID:-$DEVELOPMENT}}
# Notarization requires Hardened Runtime and a secure timestamp; only Developer ID builds get notarized.
case "$IDENTITY" in "Developer ID Application"*) FLAGS="--options runtime --timestamp" ;; esac
codesign --force $FLAGS --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"
echo "Built $APP — run: open $APP"
