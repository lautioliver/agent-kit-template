#!/usr/bin/env bash
# Prepara la implementación de un issue: valida que se pueda tomar, lo asigna
# y crea la rama. Imprime el contexto del issue para el agente.
# Uso: preparar.sh <n°issue> [--revisar] [--worktree]
#   --revisar:  solo valida e imprime; no asigna ni crea la rama.
#   --worktree: crea (o retoma) la rama en su propio worktree, ../<repo>-wt/<n>,
#               sin tocar el checkout actual. Imprime "Worktree: <ruta>".
set -euo pipefail
USO="Uso: $0 <n°issue> [--revisar] [--worktree]"
N="${1:?$USO}"; N="${N#\#}"; shift
REVISAR=""; WORKTREE=""
for opcion in "$@"; do
  case "$opcion" in
    --revisar) REVISAR=1 ;;
    --worktree) WORKTREE=1 ;;
    *) echo "$USO" >&2; exit 64 ;;
  esac
done
[[ "$N" =~ ^[0-9]+$ ]] || { echo "$USO" >&2; exit 64; }
BASE="${BASE:-<RAMA_BASE>}"   # el init de la plantilla reemplaza <RAMA_BASE>
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
YO=$(gh api user -q .login)

issue=$(gh api "repos/$REPO/issues/$N")
error() { echo "NO SE PUEDE TOMAR #$N: $*" >&2; exit 1; }

[ "$(jq -r '.pull_request // empty' <<<"$issue")" ] && error "es un PR, no un issue."
[ "$(jq -r .state <<<"$issue")" = "open" ] || error "está cerrado."
if [ "$(jq -r '(.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0)' <<<"$issue")" = "true" ]; then
  ver=""
  [ -f .claude/skills/estado/disponibles.sh ] && ver=" (ver .claude/skills/estado/disponibles.sh)"
  error "es una épica con sub-issues abiertos. Implementá sus sub-issues$ver."
fi
# Las dependencias de issues son una función nueva de GitHub: si el repo no la tiene (404), se sigue sin bloqueos.
bloq=""
if deps=$(gh api "repos/$REPO/issues/$N/dependencies/blocked_by" 2>/dev/null); then
  bloq=$(jq -r '[.[] | select(.state == "open") | "#\(.number) \(.title)"] | join("; ")' <<<"$deps")
fi
[ -n "$bloq" ] && error "está bloqueado por: $bloq"
otros=$(jq -r --arg yo "$YO" '[.assignees[].login | select(. != $yo)] | join(", ")' <<<"$issue")
[ -n "$otros" ] && error "ya está asignado a $otros."

titulo=$(jq -r .title <<<"$issue")
# Rama: claude/<n>-<descripcion>, minúsculas, sin tildes, solo [a-z0-9-], ≤ 50 caracteres.
slug=$(printf '%s' "$titulo" | perl -CS -MUnicode::Normalize -ne 'print lc NFD($_) =~ s/\pM//gr' \
  | perl -pe 's/[^a-z0-9]+/-/g; s/^-+|-+$//g; s/^(.{1,40})(-.*)?$/$1/ if length > 40')
RAMA="claude/$N-$slug"
# El worktree va al lado del checkout principal (el primero de la lista), aunque esto
# se corra desde otro worktree.
if [ -n "$WORKTREE" ]; then
  raiz=$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
  raiz=$(cd "$raiz" && pwd -P)
  WT="$(dirname "$raiz")/$(basename "$raiz")-wt/$N"
fi

echo "# Issue #$N: $titulo"
echo "Labels: $(jq -r '[.labels[].name] | join(", ")' <<<"$issue")"
echo "URL: $(jq -r .html_url <<<"$issue")"
# gh imprime el JSON del 404 en stdout cuando no hay épica: se usa el código de salida.
if padre=$(gh api "repos/$REPO/issues/$N/parent" 2>/dev/null); then
  echo "Épica: $(jq -r '"#\(.number) \(.title)"' <<<"$padre")"
fi
bloquea=""
if deps=$(gh api "repos/$REPO/issues/$N/dependencies/blocking" 2>/dev/null); then
  bloquea=$(jq -r '[.[] | select(.state == "open") | "#\(.number)"] | join(", ")' <<<"$deps")
fi
[ -n "$bloquea" ] && echo "Bloquea a: $bloquea (al cerrarse este, se desbloquean)"
echo
jq -r '.body // "(sin cuerpo)"' <<<"$issue"
comentarios=$(gh api "repos/$REPO/issues/$N/comments" -q '.[] | "\n--- @\(.user.login):\n\(.body)"')
[ -n "$comentarios" ] && { echo; echo "## Comentarios"; echo "$comentarios"; }
echo

if [ -n "$REVISAR" ]; then
  echo "(--revisar: no se asignó ni se creó la rama. Rama propuesta: $RAMA${WORKTREE:+, worktree propuesto: $WT})"
  exit 0
fi

# Varios agentes en paralelo pueden chocar en los locks de .git: se reintenta solo eso.
traer() {
  local intento err
  for intento in 1 2 3; do
    err=$(git fetch -q origin "$BASE" 2>&1) && return 0
    grep -Eq "\.lock'|cannot lock ref" <<<"$err" || break
    [ "$intento" -lt 3 ] && sleep "$intento"
  done
  echo "$err" >&2; return 1
}

# Dónde está ya la rama (si está). prune olvida los worktrees cuya carpeta se borró a mano.
git worktree prune
en_uso=$(git worktree list --porcelain | awk -v r="branch refs/heads/$RAMA" '/^worktree /{w=substr($0, 10)} $0 == r {print w}')
if [ -n "$en_uso" ]; then
  [ -d "$en_uso" ] || error "la rama $RAMA está en un worktree bloqueado cuya carpeta no existe ($en_uso). Si nadie lo usa: git worktree unlock \"$en_uso\" && git worktree prune"
  en_uso=$(cd "$en_uso" && pwd -P)
fi

if [ -z "$WORKTREE" ]; then
  [ -n "$(git status --porcelain)" ] && error "hay cambios sin commitear en el working tree."
  actual=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
  [ -n "$en_uso" ] && [ "$en_uso" != "$actual" ] && error "la rama $RAMA ya está en uso en otro worktree: $en_uso"
  gh issue edit "$N" -R "$REPO" --add-assignee @me >/dev/null
  traer
  if git show-ref -q --verify "refs/heads/$RAMA"; then
    git switch -q "$RAMA"; echo "Rama existente: $RAMA (retomando)"
  else
    git switch -q -c "$RAMA" "origin/$BASE"; echo "Rama nueva: $RAMA (desde origin/$BASE)"
  fi
  echo "Asignado a @$YO."
  exit 0
fi

# --worktree: se valida y se crea el worktree antes de asignar, así una falla no deja el issue asignado.
[ -n "$en_uso" ] && [ "$en_uso" != "$WT" ] && error "la rama $RAMA ya está en uso en otro worktree: $en_uso"
if [ -n "$en_uso" ]; then
  [ -n "$(git -C "$WT" status --porcelain)" ] && error "hay cambios sin commitear en el worktree $WT."
elif [ -e "$WT" ]; then
  error "$WT ya existe y no es el worktree de $RAMA."
fi
traer
if [ -n "$en_uso" ]; then
  echo "Rama existente: $RAMA (retomando)"
elif git show-ref -q --verify "refs/heads/$RAMA"; then
  mkdir -p "$(dirname "$WT")"; git worktree add -q "$WT" "$RAMA"
  echo "Rama existente: $RAMA (retomando)"
else
  mkdir -p "$(dirname "$WT")"; git worktree add -q --no-track -b "$RAMA" "$WT" "origin/$BASE"
  echo "Rama nueva: $RAMA (desde origin/$BASE)"
fi
gh issue edit "$N" -R "$REPO" --add-assignee @me >/dev/null
echo "Worktree: $WT"
echo "Asignado a @$YO."
