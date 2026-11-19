#!/bin/sh
# Packs OpenPaste.app into OpenPaste.dmg with an Applications shortcut for drag-to-install.
set -e
cd "$(dirname "$0")"
[ -d OpenPaste.app ] || ./build.sh
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R OpenPaste.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f OpenPaste.dmg
hdiutil create -volname OpenPaste -srcfolder "$STAGE" -format UDZO -fs HFS+ OpenPaste.dmg >/dev/null
echo "Built OpenPaste.dmg"
