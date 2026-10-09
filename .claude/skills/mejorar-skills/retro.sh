#!/usr/bin/env bash
# Guarda una retro del flujo con agentes como un archivo en la rama huérfana
# agentes/retros (retros/AAAA-MM-DD-<skill>-<n>.md). No usa GitHub: solo git.
# Escribe con plumbing (índice temporal), así no cambia la rama actual ni el
# índice, y reintenta si otro pusheó antes.
# Uso: retro.sh <archivo.md>                        publica una retro
#      retro.sh --consolidado <commit> <link al PR>  marca lo consolidado (lo usa /mejorar-skills)
set -euo pipefail
PLANTILLA="$(dirname "$0")/plantilla-retro.md"
if [ $# -eq 0 ]; then
  echo "Uso: $0 <archivo.md>. Formato de la retro:"; echo
  cat "$PLANTILLA"; exit 0
fi
RAMA=agentes/retros
cd "$(git rev-parse --show-toplevel)"
REMOTO=""
git remote get-url origin >/dev/null 2>&1 && REMOTO=origin
hoy=$(date -u +%Y-%m-%d)

# Valor de un campo del frontmatter (entre las dos primeras líneas ---).
campo() { awk -v c="$1" 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1 && index($0, c": ")==1{sub(/^[^:]*: */, ""); print; exit}' "$2"; }

if [ "$1" = "--consolidado" ]; then
  if [ $# -ne 3 ] || ! [[ "$2" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "Uso: $0 --consolidado <commit> <link al PR>" >&2; exit 64
  fi
  contenido=$(mktemp); trap 'rm -f "$contenido"' EXIT
  printf 'consolidado-hasta: %s\npr: %s\nfecha: %s\n' "$2" "$3" "$hoy" >"$contenido"
  destino() { echo consolidado.md; }
  mensaje="mejorar-skills: consolidado hasta $2"
else
  ARCHIVO="$1"
  [ -s "$ARCHIVO" ] || { echo "retro.sh: $ARCHIVO está vacío." >&2; exit 1; }
  skill=$(campo skill "$ARCHIVO"); issue=$(campo issue "$ARCHIVO"); issue="${issue#\#}"
  case "$skill" in implement-issue|review-pr|mejorar-skills) ;; *)
    echo "retro.sh: falta 'skill:' (implement-issue o review-pr) en el frontmatter. Formato:" >&2; cat "$PLANTILLA" >&2; exit 1;;
  esac
  [[ "$issue" =~ ^[0-9]+$ ]] || { echo "retro.sh: falta 'issue: <n>' en el frontmatter." >&2; exit 1; }
  sha=$(git log -1 --format=%h -- ".claude/skills/$skill/SKILL.md"); sha="${sha:-desconocido}"
  # Agrega fecha y skill_sha antes del cierre del frontmatter.
  contenido=$(mktemp); trap 'rm -f "$contenido"' EXIT
  awk -v f="$hoy" -v s="$sha" 'NR>1 && $0=="---" && !h {print "fecha: " f; print "skill_sha: " s; h=1} {print}' "$ARCHIVO" >"$contenido"
  base="retros/$hoy-$skill-$issue"
  # Si ya hay una retro de la misma skill e issue hoy, sufijo -2, -3…
  destino() {
    local d="$base.md" i=2
    while git cat-file -e "$1:$d" 2>/dev/null; do d="$base-$i.md"; i=$((i + 1)); done
    echo "$d"
  }
  mensaje="retro: $skill #$issue"
fi

blob=$(git hash-object -w "$contenido")
idx=$(mktemp -d); trap 'rm -rf "$idx" "$contenido"' EXIT
for intento in 1 2 3 4 5; do
  if [ -n "$REMOTO" ]; then
    git fetch -q "$REMOTO" "+refs/heads/$RAMA:refs/remotes/$REMOTO/$RAMA" 2>/dev/null || true
    padre=$(git rev-parse -q --verify "refs/remotes/$REMOTO/$RAMA" || true)
  else
    padre=$(git rev-parse -q --verify "refs/heads/$RAMA" || true)
  fi
  rm -f "$idx/index"
  if [ -n "$padre" ]; then
    GIT_INDEX_FILE="$idx/index" git read-tree "$padre"; ruta=$(destino "$padre")
  else
    ruta=$(destino "$(git hash-object -t tree /dev/null)")
  fi
  GIT_INDEX_FILE="$idx/index" git update-index --add --cacheinfo "100644,$blob,$ruta"
  arbol=$(GIT_INDEX_FILE="$idx/index" git write-tree)
  commit=$(git commit-tree "$arbol" ${padre:+-p "$padre"} -m "$mensaje")
  if [ -z "$REMOTO" ]; then
    git update-ref "refs/heads/$RAMA" "$commit" ${padre:+"$padre"}; echo "Retro guardada en $RAMA:$ruta (solo local, sin remoto)."; exit 0
  fi
  if git push -q "$REMOTO" "$commit:refs/heads/$RAMA" 2>/dev/null; then
    git update-ref "refs/remotes/$REMOTO/$RAMA" "$commit"
    echo "Retro guardada en $RAMA:$ruta"; exit 0
  fi
  echo "Otro pusheó a $RAMA antes; reintento ($intento/5)…" >&2
  sleep $((intento))
done
echo "retro.sh: no pude pushear a $RAMA después de 5 intentos. La retro quedó en $contenido; guardala antes de cerrar." >&2
trap - EXIT; exit 1
