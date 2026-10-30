#!/bin/zsh
# Captures du mode téléphone en portrait sur le Mac (docs/MOBILE-PORTRAIT.md §5.2), avec l'Empire inventé de
# godot/tests/etat-demo.json servi par le faux relais (chaîne des vecteurs de test, docs/SYNC-VECTEURS.json).
# Usage : tools/capture-portrait.sh <scène> [taille] [dossier]
#   scènes : pairing overview near peek full cockpit today week journal senate villages settings about leaves erase
#            banner toast pinch fling mac (le Mac en 1280 × 720, hors mode téléphone, mêmes données)
#   tailles : ref (540 × 1170 px, 1,3125 : 411 × 891 dp, l'émulateur et le Pixel), small (540 × 1110, 1,5 : 360 × 740 dp),
#             notch (ref avec un poinçon de 48 dp en haut)
# Écrit godot/override.cfg (taille de la fenêtre : --resolution est ignoré par ce projet) et le supprime en sortant ; ne
# touche ni aux réglages du jeu ni à une chaîne existante (chaine.cfg temporaire, passé par AIMPIRE_CHAINE). Image dans
# build/captures-portrait/<scène>-<taille>.png, puis tests/audit_portrait.gd liste ce qui dépasse (code 1 s'il y a lieu).
# PAGES=n : les listes qui défilent descendent page par page (<scène>-<taille>-p2.png, …), chaque page contrôlée.
set -euo pipefail
cd "$(dirname "$0")/.."
SCENE=${1:?scène}
TAILLE=${2:-ref}
SORTIE=${3:-build/captures-portrait}
mkdir -p "$SORTIE"
TMP=$(mktemp -d)
OVERRIDE=godot/override.cfg
PIDS=()
nettoyer() { rm -f "$OVERRIDE"; rm -rf "$TMP"; for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap nettoyer EXIT INT TERM

case $TAILLE in
  ref)   L=540; H=1170; DENSITE=1.3125; ZONE="" ;;
  small) L=540; H=1110; DENSITE=1.5; ZONE="" ;;
  notch) L=540; H=1170; DENSITE=1.3125; ZONE="48,0,0,0" ;;
  *) echo "taille inconnue : $TAILLE"; exit 2 ;;
esac
[[ $SCENE == mac ]] && { L=1280; H=720; }
printf '[display]\nwindow/size/window_width_override=%d\nwindow/size/window_height_override=%d\n' $L $H > "$OVERRIDE"

PORT=8787
if ! nc -z 127.0.0.1 $PORT 2>/dev/null; then
  node tools/faux-relais.mjs --port $PORT --etat godot/tests/etat-demo.json > "$TMP/relais.log" 2>&1 &
  PIDS+=($!)
  for i in {1..50}; do nc -z 127.0.0.1 $PORT 2>/dev/null && break; sleep 0.1; done
fi
RELAIS=http://127.0.0.1:$PORT/
[[ $SCENE == banner ]] && RELAIS=http://127.0.0.1:9/   # port fermé : « Relay unreachable »
printf '[chaine]\nsecret="000102030405060708090a0b0c0d0e0f"\nrelais="%s"\n' "$RELAIS" > "$TMP/chaine.cfg"

typeset -A ENV
ENV=(AIMPIRE_MOBILE 1 AIMPIRE_DENSITE $DENSITE AIMPIRE_CHAINE "$TMP/chaine.cfg" AIMPIRE_UPDATE_URL "http://127.0.0.1:$PORT/update.json")
[[ -n $ZONE ]] && ENV[AIMPIRE_ZONE_SURE]=$ZONE
IMAGES=200
VILLAGE=/srv/demo/harbor
case $SCENE in
  pairing)  ENV[AIMPIRE_CHAINE]="$TMP/absente.cfg" ;;
  overview) ;;
  near)     ENV[AIMPIRE_ZOOM]=18 ;;
  peek)     ENV[AIMPIRE_SELECT]=$VILLAGE; ENV[AIMPIRE_BATIMENT]=demo-0-0 ;;
  full)     ENV[AIMPIRE_SELECT]=$VILLAGE; ENV[AIMPIRE_BATIMENT]=demo-0-0; ENV[AIMPIRE_DETENTE]=pleine ;;
  cockpit)  ENV[AIMPIRE_FEUILLE]=cockpit ;;
  today|week|journal|villages|senate|settings) ENV[AIMPIRE_FEUILLE]=$SCENE ;;
  about|leaves|erase) ENV[AIMPIRE_APROPOS]=$SCENE ;;
  banner)   IMAGES=150 ;;
  toast)    ENV[AIMPIRE_TEST_COMMANDE]="/reglage?cle=privacy&val=flou"; ENV[AIMPIRE_AUDIT_TOAST]=1; IMAGES=60 ;;
  pinch)    ENV[AIMPIRE_GESTE]=pinch-out; IMAGES=78 ;;
  fling)    ENV[AIMPIRE_GESTE]=fling; IMAGES=74 ;;
  mac)      ENV=(AIMPIRE_UPDATE_URL "http://127.0.0.1:$PORT/update.json") ;;
  *) echo "scène inconnue : $SCENE"; exit 2 ;;
esac

if [[ $SCENE == mac ]]; then   # le Mac lit /state d'un serveur local : un petit serveur sert le même Empire inventé
  mkdir -p "$TMP/donnees" && echo jeton > "$TMP/donnees/token"
  node -e '
    const http = require("http"), fs = require("fs");
    const lu = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const t0 = Date.now() - (Date.now() % 60000);
    const abs = (o) => Array.isArray(o) ? o.map(abs) : (o && typeof o === "object") ? Object.fromEntries(Object.entries(o).map(([k, v]) => [k, ["since", "last", "t", "retourA"].includes(k) && typeof v === "number" && v <= 0 ? t0 + v : abs(v)])) : o;
    const d = abs(lu);
    const r = { "/state": d.etat, "/digest": { since: Date.now(), attention: 0, commits: 0, testsOk: 0, villages: [] },
      "/rapport": { texte: d.annexes.rapport.jour }, "/journal": { entrees: d.annexes.journal }, "/health": { ok: true } };
    http.createServer((q, s) => { const p = new URL(q.url, "http://x").pathname; s.writeHead(r[p] ? 200 : 404, { "Content-Type": "application/json" }); s.end(JSON.stringify(r[p] || {})); }).listen(7798, "127.0.0.1");
  ' godot/tests/etat-demo.json &
  PIDS+=($!)
  ENV[AIMPIRE_PORT]=7798
  ENV[AIMPIRE_HOME]="$TMP/donnees"
  for i in {1..50}; do nc -z 127.0.0.1 7798 2>/dev/null && break; sleep 0.1; done
fi

IMAGE="$SORTIE/$SCENE-$TAILLE.png"
[[ $SCENE == mac ]] && IMAGE="$SORTIE/mac.png"
ARGS=()
for k v in ${(kv)ENV}; do ARGS+=("$k=$v"); done
set +e
env "${ARGS[@]}" AIMPIRE_AUDIT_SORTIE="${IMAGE:a}" AIMPIRE_AUDIT_IMAGES=$IMAGES AIMPIRE_AUDIT_PAGES=${PAGES:-1} godot --path godot -s tests/audit_portrait.gd 2>&1 \
  | grep -v -E "^(Godot Engine|Vulkan|Metal|OpenGL|WARNING: (Not|Blend))" | grep -v "^$"
CODE=${pipestatus[1]}
set -e
echo "→ $IMAGE"
exit $CODE
