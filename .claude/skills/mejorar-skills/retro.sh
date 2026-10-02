#!/usr/bin/env bash
# Publica una retro del flujo con agentes como comentario en el issue fijado
# "Retros del flujo con agentes". Si el issue no existe, lo crea y lo fija.
# Uso: retro.sh <archivo.md>
set -euo pipefail
if [ $# -eq 0 ]; then
  echo "Uso: $0 <archivo.md>. Formato de la retro:"; echo
  cat "$(dirname "$0")/plantilla-retro.md"; exit 0
fi
ARCHIVO="$1"
[ -s "$ARCHIVO" ] || { echo "retro.sh: $ARCHIVO está vacío." >&2; exit 1; }
TITULO="Retros del flujo con agentes"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

n=$(gh issue list -R "$REPO" --state open --search "\"$TITULO\" in:title" --json number,title \
  -q ".[] | select(.title == \"$TITULO\") | .number" | head -1)
if [ -z "$n" ]; then
  cuerpo=$(mktemp)
  cat > "$cuerpo" <<'MD'
Acá se acumulan las retros del flujo con agentes: una por cada uso de `/implement-issue` y `/review-pr`.
`/mejorar-skills` las lee y propone ajustes a las skills **siempre en un PR**. No cerrar este issue.
MD
  url=$(gh issue create -R "$REPO" --title "$TITULO" --body-file "$cuerpo")
  rm -f "$cuerpo"
  n="${url##*/}"
  gh issue pin "$n" -R "$REPO" >/dev/null 2>&1 || echo "Aviso: no pude fijar el issue #$n; fijalo a mano." >&2
  echo "Creé el issue #$n para las retros."
fi
gh issue comment "$n" -R "$REPO" --body-file "$ARCHIVO"
