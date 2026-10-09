#!/usr/bin/env bash
# Guarda una retro del flujo con agentes como un archivo en la rama huérfana
# agentes/retros (retros/AAAA-MM-DD-<skill>-<n>.md). No usa GitHub: solo git.
# Escribe con plumbing (índice temporal), así no cambia la rama actual ni el
# índice, y reintenta si otro escribió antes. Si no puede guardarla, la deja en
# <.git común>/retros-pendientes/ para reintentar con el mismo comando.
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
# El .git común (no el del worktree, que se borra con git worktree remove).
PENDIENTES="$(git rev-parse --path-format=absolute --git-common-dir)/retros-pendientes"
hoy=$(date -u +%Y-%m-%d)
contenido=$(mktemp); idx=$(mktemp -d)
modo=""; guardado=0

# Si algo falla después de preparar la retro (cualquier comando, no solo el push),
# la retro queda en pendientes en vez de perderse.
# shellcheck disable=SC2329  # la invoca el trap EXIT
al_salir() {
  if [ "$modo" = retro ] && [ "$guardado" = 0 ]; then
    mkdir -p "$PENDIENTES"; pendiente="$PENDIENTES/${base##*/}-$$.md"
    cp "$contenido" "$pendiente"
    echo "retro.sh: no pude guardar en $RAMA. Quedó en $pendiente; reintentá con: $0 $pendiente" >&2
  fi
  rm -rf "$contenido" "$idx"
}
trap al_salir EXIT

# La punta de la rama de retros: la del remoto si existe; si no, la local
# (retros guardadas antes de tener remoto).
punta() {
  if [ -n "$REMOTO" ]; then
    git fetch -q "$REMOTO" "+refs/heads/$RAMA:refs/remotes/$REMOTO/$RAMA" 2>/dev/null || true
    git rev-parse -q --verify "refs/remotes/$REMOTO/$RAMA" && return
  fi
  git rev-parse -q --verify "refs/heads/$RAMA" || true
}

# Frontmatter normalizado: sin CRLF y sin comillas alrededor de los valores.
# Falla si no hay un frontmatter cerrado al principio.
frontmatter() {
  tr -d '\r' <"$1" | awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{c=1; exit} NR>1{print} END{exit !c}' \
    | sed -E 's/^([a-z_]+): *"(.*)" *$/\1: \2/; s/^([a-z_]+): *'"'"'(.*)'"'"' *$/\1: \2/'
}
campo() { sed -n "s/^$1: *//p" <<<"$2" | head -1; }

if [ "$1" = "--consolidado" ]; then
  # Solo un commit de la rama de retros: con otro, senales.sh volvería a mostrar todo.
  p=$(punta)
  if [ $# -ne 3 ] || ! hasta=$(git rev-parse -q --verify "$2^{commit}") || [ -z "$p" ] \
    || ! git merge-base --is-ancestor "$hasta" "$p"; then
    echo "Uso: $0 --consolidado <commit de $RAMA que imprimió senales.sh> <link al PR>" >&2; exit 64
  fi
  printf 'consolidado-hasta: %s\npr: %s\nfecha: %s\n' "$hasta" "$3" "$hoy" >"$contenido"
  base=consolidado; mensaje="mejorar-skills: consolidado hasta $hasta"
else
  ARCHIVO="$1"
  [ -s "$ARCHIVO" ] || { echo "retro.sh: $ARCHIVO no existe o está vacío." >&2; exit 1; }
  if ! fm=$(frontmatter "$ARCHIVO"); then
    echo "retro.sh: la retro tiene que empezar con un frontmatter entre dos líneas ---. Formato:" >&2
    cat "$AQUI/plantilla-retro.md" >&2; exit 1
  fi
  skill=$(campo skill "$fm"); issue=$(campo issue "$fm"); pr=$(campo pr "$fm")
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
  sha=$(git log -1 --format=%H -- ".claude/skills/$skill/SKILL.md"); sha="${sha:-desconocido}"
  # Retro normalizada, con fecha y skill_sha (si no están: una pendiente ya los tiene).
  {
    echo ---; echo "$fm"
    grep -q '^fecha: ' <<<"$fm" || echo "fecha: $hoy"
    grep -q '^skill_sha: ' <<<"$fm" || echo "skill_sha: $sha"
    echo ---; tr -d '\r' <"$ARCHIVO" | awk 'NR>1 && $0=="---" && !c {c=1; next} c'
  } >"$contenido"
  base="retros/$hoy-$skill-$n"; mensaje="retro: $skill $n"; modo=retro
fi
blob=$(git hash-object -w "$contenido")
nulo=$(printf '%0*d' "${#blob}" 0)   # 40 o 64 caracteres según el formato del repo

for intento in 1 2 3 4 5; do
  padre=$(punta)
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
    git update-ref "refs/heads/$RAMA" "$commit" "${padre:-$nulo}" 2>/dev/null && guardado=1
  elif err=$(git push -q "$REMOTO" "$commit:refs/heads/$RAMA" 2>&1); then
    git update-ref "refs/remotes/$REMOTO/$RAMA" "$commit"; guardado=1
  elif ! grep -Eq '\[rejected\]|non-fast-forward|fetch first|cannot lock ref' <<<"$err"; then
    # Auth, red, rama protegida: reintentar no sirve.
    echo "retro.sh: falló el push a $RAMA:" >&2; echo "$err" >&2; break
  fi
  if [ "$guardado" = 1 ]; then
    if [ -n "$REMOTO" ]; then echo "Guardado en $RAMA:$ruta"; else echo "Guardado en $RAMA:$ruta (solo local: no hay remoto origin)."; fi
    # Si era una pendiente, ya no hace falta.
    if [ "$modo" = retro ] && [ "$(cd "$(dirname "$ARCHIVO")" && pwd -P)" = "$(cd "$PENDIENTES" 2>/dev/null && pwd -P)" ]; then
      rm -f "$ARCHIVO"
    fi
    exit 0
  fi
  [ "$intento" -lt 5 ] || break
  echo "Otro escribió en $RAMA antes; reintento ($intento/4)…" >&2
  sleep "$intento"
done
[ "$modo" = retro ] || echo "retro.sh: no pude marcar lo consolidado; volvé a correr el mismo comando." >&2
exit 1
