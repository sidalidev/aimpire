#!/bin/zsh
# Publishes a package: sha256 checksum, merged update.json (mac + android), copy to the server that hosts the relay
# (served by the relay on $AIMPIRE_BASE/update.json and /download/<file>), then GitHub release v<version> with the
# package and its .sha256 file.
# Usage: tools/publier-maj.sh mac|android <file> <version>     (called by tools/release-macos.sh and release-android.sh)
# Environment:
#   AIMPIRE_VPS            SSH target of the relay server, e.g. user@example.org (required to publish)
#   AIMPIRE_RELEASES_DIR   folder on that server mounted read-only into the relay as /releases (required to publish)
#   AIMPIRE_BASE           public URL of the relay (default https://aimpire.sidali.dev)
#   AIMPIRE_PUBLIER=0      only builds update.json in build/publication/, sends nothing
set -euo pipefail
cd "$(dirname "$0")/.."
PLAT=$1 FICHIER=$2 VERSION=$3
NOM=${FICHIER:t}
BASE=${AIMPIRE_BASE:-https://aimpire.sidali.dev}
PUB=build/publication
mkdir -p $PUB

if [[ ${AIMPIRE_PUBLIER:-1} != 0 ]]; then
  if [[ -z ${AIMPIRE_VPS:-} || -z ${AIMPIRE_RELEASES_DIR:-} ]]; then
    echo "error: set AIMPIRE_VPS (e.g. user@example.org) and AIMPIRE_RELEASES_DIR (e.g. /srv/aimpire/releases)," >&2
    echo "       or run with AIMPIRE_PUBLIER=0 to build update.json without sending anything." >&2
    exit 1
  fi
  VPS=$AIMPIRE_VPS
  DOSSIER=$AIMPIRE_RELEASES_DIR
fi

echo "> publishing $PLAT $VERSION: $NOM"
SHA=$(shasum -a 256 "$FICHIER" | cut -d' ' -f1)
TAILLE=$(stat -f %z "$FICHIER")
echo "  sha256 $SHA  ($TAILLE bytes)"
# checksum file next to the package, in the format `shasum -a 256 -c` expects
SOMME=$PUB/$NOM.sha256
echo "$SHA  $NOM" > $SOMME
# release notes: the "## <version>" section of CHANGELOG.md
awk -v v="$VERSION" '/^## /{dedans = (index($0, "## " v " ") == 1)} dedans' CHANGELOG.md > $PUB/notes.md
TITRE=$(head -1 $PUB/notes.md | sed 's/^## [^:]*: *//')
tail -n +2 $PUB/notes.md > $PUB/notes-corps.md

if [[ ${AIMPIRE_PUBLIER:-1} == 0 ]]; then
  echo '{}' > $PUB/update-distant.json
else
  ssh $VPS "mkdir -p $DOSSIER && cat $DOSSIER/update.json 2>/dev/null || true" > $PUB/update-distant.json
fi
node tools/publier-maj.mjs --existant $PUB/update-distant.json --plateforme $PLAT --version $VERSION \
  --url "$BASE/download/$NOM" --sha256 $SHA --taille $TAILLE --notes $PUB/notes-corps.md > $PUB/update.json
cat $PUB/update.json
[[ ${AIMPIRE_PUBLIER:-1} == 0 ]] && { echo "  AIMPIRE_PUBLIER=0: nothing sent"; exit 0; }

echo "> copying to the server"
chmod 644 "$FICHIER" $PUB/update.json
scp -q "$FICHIER" "$VPS:$DOSSIER/$NOM"
scp -q $PUB/update.json "$VPS:$DOSSIER/update.json.tmp"
ssh $VPS "chmod 644 $DOSSIER/$NOM $DOSSIER/update.json.tmp && mv -f $DOSSIER/update.json.tmp $DOSSIER/update.json"

echo "> checking"
curl -fsS "$BASE/update.json" | grep -q "/$NOM\"" && echo "  update.json is live" || echo "  update.json not updated yet (is the relay deployed?)"
LONGUEUR=$(curl -fsSI "$BASE/download/$NOM" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{print $2}')
[[ "$LONGUEUR" == "$TAILLE" ]] && echo "  $BASE/download/$NOM: $LONGUEUR bytes" || echo "  check the download: length \"$LONGUEUR\" instead of $TAILLE"

echo "> GitHub release v$VERSION"
if gh release view "v$VERSION" > /dev/null 2>&1; then
  gh release upload "v$VERSION" "$FICHIER" "$SOMME" --clobber
else
  gh release create "v$VERSION" "$FICHIER" "$SOMME" --target main --title "AImpire $VERSION: $TITRE" --notes-file $PUB/notes-corps.md
fi
echo "  $(gh release view "v$VERSION" --json url -q .url)"
