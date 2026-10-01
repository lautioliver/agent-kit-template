#!/usr/bin/env bash
# Reemplaza los marcadores de la plantilla y se borra solo.
# Uso: ./scripts/init-plantilla.sh "Nombre del proyecto" [rama-base]
set -euo pipefail
export P="${1:?Uso: $0 \"Nombre del proyecto\" [rama-base]}"
export B="${2:-main}"
cd "$(git rev-parse --show-toplevel)"
grep -rlE '<PROYECTO>|<RAMA_BASE>' --exclude-dir=.git --exclude=init-plantilla.sh . \
  | xargs perl -pi -e 's/<PROYECTO>/$ENV{P}/g; s/<RAMA_BASE>/$ENV{B}/g'
rm -- scripts/init-plantilla.sh
echo "Listo. Pendientes (TODO:):"
grep -rn "TODO:" --exclude-dir=.git . | cut -c1-120 || true
