#!/bin/zsh
# Développement : lance le serveur (s'il ne tourne pas) puis le jeu. `./aimpire.sh pip` démarre en incrustation.
# Les données vivent dans ~/Library/Application Support/AImpire (AIMPIRE_HOME pour changer), le journal dans logs/server.log.
cd "$(dirname "$0")"
PORT=${AIMPIRE_PORT:-7777}
if ! curl -s -o /dev/null "127.0.0.1:$PORT/health"; then
  node daemon/server.js --parent-pid=$$ &
  for i in {1..30}; do curl -s -o /dev/null "127.0.0.1:$PORT/health" && break; sleep 0.2; done
fi
if [[ "$1" == "pip" ]]; then godot --path godot -- --pip; else godot --path godot; fi
