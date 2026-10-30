#!/bin/zsh
# Construit build/AImpire.apk (arm64, signé) pour le mode téléphone (docs/SYNC.md §7 et §8).
# Keystore de publication : ~/.aimpire/release.jks, créé au premier passage (alias aimpire, RSA 4096, 10 000 jours) ;
# son mot de passe est tiré au hasard et rangé dans ~/.aimpire/keystore.properties (0600), jamais dans le dépôt.
# Puis publie l'APK (tools/publier-maj.sh : update.json, VPS, release GitHub ; AIMPIRE_PUBLIER=0 pour ne rien envoyer).
# Usage : tools/release-android.sh
# Variables : JAVA_HOME (défaut openjdk@21 de Homebrew), ANDROID_HOME (défaut ~/Library/Android/sdk).
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
CLES=$HOME/.aimpire
JKS=$CLES/release.jks
PROPS=$CLES/keystore.properties
APK=build/AImpire.apk
BUILD_TOOLS=$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -1)
test -x "$BUILD_TOOLS/apksigner" || { echo "apksigner introuvable dans $ANDROID_HOME/build-tools"; exit 1; }
test -x "$JAVA_HOME/bin/keytool" || { echo "keytool introuvable dans $JAVA_HOME"; exit 1; }

echo "▸ keystore"
mkdir -p "$CLES" && chmod 700 "$CLES"
if [[ ! -f "$JKS" ]]; then
  MDP=$(openssl rand -hex 24)
  umask 077
  printf 'storeFile=%s\nkeyAlias=aimpire\nstorePassword=%s\nkeyPassword=%s\n' "$JKS" "$MDP" "$MDP" > "$PROPS"
  "$JAVA_HOME/bin/keytool" -genkeypair -noprompt -keystore "$JKS" -storetype PKCS12 -alias aimpire \
    -keyalg RSA -keysize 4096 -validity 10000 -storepass "$MDP" -keypass "$MDP" \
    -dname "CN=AImpire, O=Sid Ali, C=FR" > /dev/null
  chmod 600 "$JKS" "$PROPS"
  echo "  créé : $JKS (mot de passe dans $PROPS)"
fi
MDP=$(sed -n 's/^storePassword=//p' "$PROPS")
test -n "$MDP" || { echo "mot de passe absent de $PROPS"; exit 1; }

echo "▸ textes de l'écran About (godot/about_texts.gd à jour)"
node tools/gen-about.mjs --check

echo "▸ export Godot (Android, arm64)"
mkdir -p build
rm -f "$APK"
godot --headless --path godot --import > /dev/null 2>&1 || true
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$JKS" GODOT_ANDROID_KEYSTORE_RELEASE_USER=aimpire GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$MDP" \
  godot --headless --path godot --export-release "Android" "../$APK" 2>&1 | grep -i "error\|warn" || true
test -f "$APK" || { echo "export raté"; exit 1; }

echo "▸ contrôles du dépôt et permissions de l'APK (docs/permissions.txt)"
node tools/check-repo.mjs "$APK"

echo "▸ vérification de la signature"
"$BUILD_TOOLS/apksigner" verify --print-certs "$APK" | grep -i "signer #1 certificate \(DN\|SHA-256\)"
echo "  $(du -h "$APK" | cut -f1)  $APK"
echo "  installer : adb install -r $APK   (GrapheneOS : transférer l'APK puis l'ouvrir)"

VERSION=$(sed -n 's/^version\/name="\(.*\)"$/\1/p' godot/export_presets.cfg)
cp "$APK" "build/aimpire-$VERSION.apk"
shasum -a 256 "build/aimpire-$VERSION.apk" | tee "build/aimpire-$VERSION.apk.sha256"
tools/publier-maj.sh android "build/aimpire-$VERSION.apk" "$VERSION"
