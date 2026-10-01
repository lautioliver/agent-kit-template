#!/usr/bin/env bash
# Reemplaza los marcadores de la plantilla y se borra solo.
# Uso: ./scripts/init-plantilla.sh "Nombre del proyecto" [rama-base]
set -euo pipefail
export P="${1:?Uso: $0 \"Nombre del proyecto\" [rama-base]}"
export B="${2:-main}"
export F="$(date +%Y-%m-%d)"
if [ "$B" = "main" ]; then
  export R='Única rama permanente `main`: los PRs de trabajo van directo a `main`.'
else
  export R="Los PRs de trabajo van a \`$B\`. \`main\` es producción y solo recibe PRs de release desde \`$B\`."
fi
cd "$(git rev-parse --show-toplevel)"
grep -rlE '<PROYECTO>|<RAMA_BASE>|<FECHA>|<REGLA_RAMAS>' --exclude-dir=.git --exclude=init-plantilla.sh . \
  | xargs perl -pi -e 's/<PROYECTO>/$ENV{P}/g; s/<RAMA_BASE>/$ENV{B}/g; s/<FECHA>/$ENV{F}/g; s/<REGLA_RAMAS>/$ENV{R}/g'
if [ "$B" != "main" ]; then
  perl -pi -e "s/branches: \[$B\]/branches: [main, $B]/" .github/workflows/labels.yml
fi
rm -- scripts/init-plantilla.sh
echo "Listo. Pendientes (TODO:):"
grep -rn "TODO:" --exclude-dir=.git . | cut -c1-120 || true
