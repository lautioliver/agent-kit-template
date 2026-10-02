#!/usr/bin/env bash
# Prepara la implementación de un issue: valida que se pueda tomar, lo asigna
# y crea la rama. Imprime el contexto del issue para el agente.
# Uso: preparar.sh <n°issue> [--revisar]
#   --revisar: solo valida e imprime; no asigna ni crea la rama.
set -euo pipefail
N="${1:?Uso: $0 <n°issue> [--revisar]}"; N="${N#\#}"
REVISAR="${2:-}"
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

if [ "$REVISAR" = "--revisar" ]; then
  echo "(--revisar: no se asignó ni se creó la rama. Rama propuesta: $RAMA)"
  exit 0
fi

[ -n "$(git status --porcelain)" ] && error "hay cambios sin commitear en el working tree."
gh issue edit "$N" -R "$REPO" --add-assignee @me >/dev/null
git fetch -q origin "$BASE"
if git show-ref -q --verify "refs/heads/$RAMA"; then
  git switch -q "$RAMA"; echo "Rama existente: $RAMA (retomando)"
else
  git switch -q -c "$RAMA" "origin/$BASE"; echo "Rama nueva: $RAMA (desde origin/$BASE)"
fi
echo "Asignado a @$YO."
