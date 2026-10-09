#!/usr/bin/env bash
# Guarda una retro del flujo con agentes como un archivo en la rama huérfana
# agentes/retros (retros/AAAA-MM-DD-<skill>-<n>.md). No usa GitHub: solo git.
# Escribe con plumbing (índice temporal), así no cambia la rama actual ni el
# índice, y reintenta si otro escribió antes.
# Uso: retro.sh <archivo.md>                        publica una retro
#      retro.sh --consolidado <commit> <link al PR>  marca lo consolidado (lo usa /mejorar-skills)
set -euo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
if [ $# -eq 0 ]; then
  echo "Uso: $0 <archivo.md>. Formato de la retro:"; echo
  cat "$AQUI/plantilla-retro.md"; exit 0
fi
# La ruta de la retro es relativa a donde se llamó, no a la raíz.
if [ "$1" != "--consolidado" ] && [ -f "$1" ]; then
  set -- "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
fi
RAMA=agentes/retros
cd "$(git rev-parse --show-toplevel)"
REMOTO=""
git remote get-url origin >/dev/null 2>&1 && REMOTO=origin
hoy=$(date -u +%Y-%m-%d)
contenido=$(mktemp); idx=$(mktemp -d)
trap 'rm -rf "$contenido" "$idx"' EXIT

# Valor de un campo del frontmatter (entre las dos primeras líneas ---).
campo() { awk -v c="$1" 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1 && index($0, c": ")==1{sub(/^[^:]*: */, ""); print; exit}' "$2"; }

if [ "$1" = "--consolidado" ]; then
  if [ $# -ne 3 ] || ! hasta=$(git rev-parse -q --verify "$2^{commit}"); then
    echo "Uso: $0 --consolidado <commit de $RAMA que imprimió senales.sh> <link al PR>" >&2; exit 64
  fi
  printf 'consolidado-hasta: %s\npr: %s\nfecha: %s\n' "$hasta" "$3" "$hoy" >"$contenido"
  base=consolidado; mensaje="mejorar-skills: consolidado hasta $hasta"
else
  ARCHIVO="$1"
  [ -s "$ARCHIVO" ] || { echo "retro.sh: $ARCHIVO no existe o está vacío." >&2; exit 1; }
  skill=$(campo skill "$ARCHIVO"); issue=$(campo issue "$ARCHIVO"); pr=$(campo pr "$ARCHIVO")
  issue="${issue#\#}"; pr="${pr#\#}"
  case "$skill" in implement-issue|review-pr|mejorar-skills) ;; *)
    echo "retro.sh: falta 'skill:' (implement-issue, review-pr o mejorar-skills) en el frontmatter. Formato:" >&2
    cat "$AQUI/plantilla-retro.md" >&2; exit 1;;
  esac
  # Identifica la retro el issue o, si no hay (un PR sin issue), el PR.
  if [[ "$issue" =~ ^[0-9]+$ ]]; then n="$issue"
  elif [[ "$pr" =~ ^[0-9]+$ ]]; then n="pr$pr"
  else echo "retro.sh: falta 'issue: <n>' o 'pr: <n>' en el frontmatter." >&2; exit 1
  fi
  sha=$(git log -1 --format=%h -- ".claude/skills/$skill/SKILL.md"); sha="${sha:-desconocido}"
  # Agrega fecha y skill_sha al frontmatter (si no están: una retro pendiente ya los tiene).
  awk -v f="$hoy" -v s="$sha" 'NR>1 && !h && /^(fecha|skill_sha): /{t[substr($0,1,index($0,":")-1)]=1}
    NR>1 && $0=="---" && !h {if(!t["fecha"])print "fecha: " f; if(!t["skill_sha"])print "skill_sha: " s; h=1} {print}' "$ARCHIVO" >"$contenido"
  base="retros/$hoy-$skill-$n"; mensaje="retro: $skill $n"
fi
blob=$(git hash-object -w "$contenido")

ref="refs/heads/$RAMA"; [ -n "$REMOTO" ] && ref="refs/remotes/$REMOTO/$RAMA"
for intento in 1 2 3 4 5; do
  [ -n "$REMOTO" ] && { git fetch -q "$REMOTO" "+refs/heads/$RAMA:$ref" 2>/dev/null || true; }
  padre=$(git rev-parse -q --verify "$ref" || true)
  rm -f "$idx/index"
  [ -n "$padre" ] && GIT_INDEX_FILE="$idx/index" git read-tree "$padre"
  # consolidado.md se reemplaza; una retro nunca pisa otra (sufijo -2, -3…).
  ruta="$base.md"; i=2
  while [ "$base" != consolidado ] && [ -n "$padre" ] && git cat-file -e "$padre:$ruta" 2>/dev/null; do
    ruta="$base-$i.md"; i=$((i + 1))
  done
  GIT_INDEX_FILE="$idx/index" git update-index --add --cacheinfo "100644,$blob,$ruta"
  arbol=$(GIT_INDEX_FILE="$idx/index" git write-tree)
  commit=$(git commit-tree "$arbol" ${padre:+-p "$padre"} -m "$mensaje")
  if [ -z "$REMOTO" ]; then
    # Compare-and-swap contra el padre leído: si otra sesión escribió en el medio, se reintenta.
    if git update-ref "$ref" "$commit" "${padre:-0000000000000000000000000000000000000000}" 2>/dev/null; then
      echo "Guardado en $RAMA:$ruta (solo local: no hay remoto origin)."; exit 0
    fi
  elif err=$(git push -q "$REMOTO" "$commit:refs/heads/$RAMA" 2>&1); then
    git update-ref "$ref" "$commit"
    echo "Guardado en $RAMA:$ruta"; exit 0
  elif ! grep -Eq '\[rejected\]|non-fast-forward|fetch first|cannot lock ref' <<<"$err"; then
    # Auth, red, rama protegida: reintentar no sirve.
    echo "retro.sh: falló el push a $RAMA:" >&2; echo "$err" >&2; break
  fi
  echo "Otro escribió en $RAMA antes; reintento ($intento/5)…" >&2
  sleep "$intento"
done
if [ "$base" = consolidado ]; then
  echo "retro.sh: no pude marcar lo consolidado; volvé a correr el mismo comando." >&2; exit 1
fi
pendiente="$(git rev-parse --absolute-git-dir)/retros-pendientes/${base##*/}-$$.md"
mkdir -p "${pendiente%/*}"; cp "$contenido" "$pendiente"
echo "retro.sh: no pude guardar en $RAMA. Quedó en $pendiente; reintentá con: $0 $pendiente" >&2
exit 1
