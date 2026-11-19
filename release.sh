#!/bin/sh
# Builds, signs, notarizes and publishes a GitHub release from this Mac.
# The company Developer ID certificate never leaves the local keychain.
#
# Usage: ./release.sh v0.2.0
# One-time setup: Developer ID Application certificate in the keychain, plus a notarytool profile:
#   xcrun notarytool store-credentials openpaste --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>
set -e
cd "$(dirname "$0")"

TAG=$1
case "$TAG" in
v[0-9]*) ;;
*) echo "usage: ./release.sh vX.Y.Z" >&2; exit 1 ;;
esac
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "Tag $TAG already exists." >&2; exit 1; }
security find-identity -v -p codesigning | grep -q "Developer ID Application" ||
    { echo "Developer ID Application certificate not found in the keychain." >&2; exit 1; }

swift test
VERSION=$TAG ./build.sh
./dmg.sh
DMG="OpenPaste-$TAG.dmg"
mv OpenPaste.dmg "$DMG"

codesign --sign "Developer ID Application" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile openpaste --wait
xcrun stapler staple "$DMG" # fails if Apple rejected the build, so nothing gets published
spctl --assess --type open --context context:primary-signature -v "$DMG"

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --generate-notes --notes "## Установка
1. Скачайте \`$DMG\` ниже, откройте и перетащите OpenPaste в «Программы».
2. Разрешите доступ: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ.

Требуется macOS 14 или новее."
echo "Released $TAG"
