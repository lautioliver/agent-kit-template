#!/usr/bin/env bash
# Reemplaza los marcadores de la plantilla y se borra solo.
# Uso: ./scripts/init-plantilla.sh "Nombre del proyecto" [rama-base] [releases]
#   rama-base: main (default) o develop.
#   releases:  solo con develop. Agrega el flujo develop → release/vX.Y.Z → main
#              para publicar versiones sin tocar producción (app con usuarios activos).
set -euo pipefail
USO="Uso: $0 \"Nombre del proyecto\" [main|develop] [releases]"
export P="${1:?$USO}"
export B="${2:-main}"
MODO="${3:-}"
if [ -n "$MODO" ] && { [ "$MODO" != "releases" ] || [ "$B" = "main" ]; }; then
  echo "$USO"; echo "'releases' solo se puede usar con la rama base develop."; exit 1
fi
export F="$(date +%Y-%m-%d)"
if [ "$B" = "main" ]; then
  export R='Única rama permanente `main`: los PRs de trabajo van directo a `main`.'
elif [ "$MODO" = "releases" ]; then
  export R="Los PRs de trabajo van a \`$B\`. Las versiones se preparan en \`release/vX.Y.Z\` (cortada desde \`$B\`, probada en staging) y recién ahí pasan a \`main\`, que es producción."
else
  export R="Los PRs de trabajo van a \`$B\`. \`main\` es producción y solo recibe PRs de release desde \`$B\`."
fi
cd "$(git rev-parse --show-toplevel)"
grep -rlE '<PROYECTO>|<RAMA_BASE>|<FECHA>|<REGLA_RAMAS>' --exclude-dir=.git --exclude=init-plantilla.sh . \
  | xargs perl -pi -e 's/<PROYECTO>/$ENV{P}/g; s/<RAMA_BASE>/$ENV{B}/g; s/<FECHA>/$ENV{F}/g; s/<REGLA_RAMAS>/$ENV{R}/g'
BLOQUES=$(grep -rl 'releases:inicio' --exclude-dir=.git --exclude=init-plantilla.sh . || true)
if [ "$MODO" = "releases" ]; then
  # Se queda el contenido; solo se sacan los marcadores.
  for f in $BLOQUES; do perl -ni -e 'print unless /<!-- releases:(inicio|fin) -->/' "$f"; done
  perl -pi -e "s/branches: \[$B\]/branches: [main, $B, 'release\/**']/" .github/workflows/labels.yml .github/workflows/docs.yml
else
  for f in $BLOQUES; do perl -0pi -e 's/\n<!-- releases:inicio -->.*?<!-- releases:fin -->\n//s' "$f"; done
  [ "$B" != "main" ] && perl -pi -e "s/branches: \[$B\]/branches: [main, $B]/" .github/workflows/labels.yml .github/workflows/docs.yml
fi
rm -- scripts/init-plantilla.sh
echo "Listo. Pendientes (TODO:):"
grep -rn "TODO:" --exclude-dir=.git . | cut -c1-120 || true
