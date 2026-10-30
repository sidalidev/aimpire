#!/bin/zsh
# Construit AImpire.app : serveur Bun embarqué, export Godot, Game Mode, signature ad hoc, zip et somme de contrôle,
# puis publie le zip (tools/publier-maj.sh : update.json, VPS, release GitHub ; AIMPIRE_PUBLIER=0 pour ne rien envoyer).
# Usage : tools/release-macos.sh [version]   (la version lue dans daemon/config.js par défaut)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-$(sed -n "s/export const VERSION = '\(.*\)';/\1/p" daemon/config.js)}
APP=build/AImpire.app
setopt +o nomatch 2>/dev/null; rm -rf build/AImpire.app build/AImpire-*.zip
mkdir -p build

echo "▸ serveur (Bun, arm64)"
(cd daemon && bun build --compile --target=bun-darwin-arm64 --outfile ../build/aimpire-server server.js > /dev/null)

echo "▸ textes de l'écran About (godot/about_texts.gd à jour)"
node tools/gen-about.mjs --check

echo "▸ export Godot"
godot --headless --path godot --export-release "macOS" "../$APP" 2>&1 | grep -iv "^$" | grep -i "error\|warn" || true
test -d "$APP" || { echo "export raté"; exit 1; }

echo "▸ serveur embarqué + Info.plist"
cp build/aimpire-server "$APP/Contents/Resources/aimpire-server"
chmod +x "$APP/Contents/Resources/aimpire-server"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSSupportsGameMode bool true" "$APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :LSSupportsGameMode true" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.games" "$APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.games" "$APP/Contents/Info.plist"

echo "▸ signature ad hoc"
codesign --force --options runtime --entitlements tools/server.entitlements --sign - "$APP/Contents/Resources/aimpire-server"
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature ok"

echo "▸ archive"
ZIP="build/AImpire-$VERSION-macos.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
du -sh "$APP" "$ZIP"

tools/publier-maj.sh mac "$ZIP" "$VERSION"
