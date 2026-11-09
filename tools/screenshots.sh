#!/usr/bin/env bash
# Captures d'écran du jeu pour la relecture (agent art-director).
# Usage : GODOT=/chemin/vers/godot tools/screenshots.sh [dossier_de_sortie]
# Sous Linux sans écran, lance-le via xvfb-run.
set -euo pipefail
GODOT="${GODOT:-godot}"
OUT="${1:-screenshots}"
mkdir -p "$OUT"
shoot() {
  local name="$1"; shift
  "$GODOT" --path . --rendering-driver opengl3 --resolution 960x1704 -- "$@" --screenshot="$OUT/$name.png"
}
shoot nouveau-joueur --fresh
shoot garage --demo
for p in atelier garage album spot offline menu; do
  shoot "fenetre-$p" --demo --popup="$p"
done
echo "Captures dans $OUT/"
