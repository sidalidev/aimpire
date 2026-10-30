#!/bin/zsh
# Icônes d'AImpire depuis un seul dessin (icon/temple.svg, grille 24, trait 2,1, bouts et angles ronds) sur l'or romain
# de la charte (#B8892A), à plat. Produit :
#   godot/icon.png                      1024 px, carré arrondi (rayon 30 %) : fenêtre, Dock pendant le développement
#   godot/build/icon-1024.png + AImpire.icns   macOS : grille d'Apple (824 px dans 1024, coins de macOS), toutes tailles
#   godot/build/android/*.png           Android : icône adaptative (premier plan, arrière-plan, monochrome) et 192 px
# Usage : tools/gen-icons.sh   (rsvg-convert et iconutil)
set -euo pipefail
cd "$(dirname "$0")/.."
OR='#B8892A'
ENCRE='#1F2A22'
TRACES=$(sed -n 's/.*<path d="\([^"]*\)".*/\1/p' icon/temple.svg)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Le dessin (viewBox 24) placé dans un carré de `cote` px : `echelle` px par unité, centré, couleur `trait`.
dessin() {   # cote echelle trait
  local cote=$1 e=$2 c=$3
  local d=$(printf "%.2f" $(( (cote - 24 * e) / 2.0 )))
  print -n "<g transform=\"translate($d $d) scale($e)\" fill=\"none\" stroke=\"$c\" stroke-width=\"2.1\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
  for p in ${(f)TRACES}; do print -n "<path d=\"$p\"/>"; done
  print -n "</g>"
}
svg() { print "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$1\" height=\"$1\" viewBox=\"0 0 $1 $1\">$2</svg>"; }
rendre() { rsvg-convert -w $2 -h $2 "$1" -o "$3"; }

# 1. Carré arrondi (rayon 30 %), dessin à 62 % du côté
svg 1024 "<rect width=\"1024\" height=\"1024\" rx=\"307\" fill=\"$OR\"/>$(dessin 1024 26.5 $ENCRE)" > $TMP/carre.svg
rendre $TMP/carre.svg 1024 godot/icon.png

# 2. macOS : 824 px centrés dans 1024 (marge de 100 px), coins de macOS (rayon 185), dessin à 62 % de la plaque
svg 1024 "<rect x=\"100\" y=\"100\" width=\"824\" height=\"824\" rx=\"185\" fill=\"$OR\"/>$(dessin 1024 21.3 $ENCRE)" > $TMP/mac.svg
rendre $TMP/mac.svg 1024 godot/build/icon-1024.png
mkdir -p $TMP/AImpire.iconset
for t in 16 32 128 256 512; do
  rendre $TMP/mac.svg $t $TMP/AImpire.iconset/icon_${t}x${t}.png
  rendre $TMP/mac.svg $((t * 2)) $TMP/AImpire.iconset/icon_${t}x${t}@2x.png
done
iconutil -c icns $TMP/AImpire.iconset -o godot/build/AImpire.icns

# 3. Android : 432 px = 108 dp ; zone sûre de 66 dp au centre, le dessin tient dans un cercle de 264 px (11 px par unité)
mkdir -p godot/build/android
svg 432 "<rect width=\"432\" height=\"432\" fill=\"$OR\"/>" > $TMP/fond.svg
svg 432 "$(dessin 432 11 $ENCRE)" > $TMP/avant.svg
svg 432 "$(dessin 432 11 '#FFFFFF')" > $TMP/mono.svg
rendre $TMP/fond.svg 432 godot/build/android/icon-background-432.png
rendre $TMP/avant.svg 432 godot/build/android/icon-foreground-432.png
rendre $TMP/mono.svg 432 godot/build/android/icon-monochrome-432.png
svg 192 "<rect width=\"192\" height=\"192\" rx=\"58\" fill=\"$OR\"/>$(dessin 192 5 $ENCRE)" > $TMP/legacy.svg
rendre $TMP/legacy.svg 192 godot/build/android/icon-192.png
echo "icônes : godot/icon.png, godot/build/icon-1024.png, godot/build/AImpire.icns, godot/build/android/"
