#!/usr/bin/env bash
# Lista los issues abiertos que se pueden empezar ya (sin bloqueantes abiertos),
# ordenados por prioridad; aparte los bloqueados con lo que los bloquea, y las
# épicas (issues con sub-issues abiertos), que se trabajan por sus sub-issues.
# Solo lee: no modifica nada.
# Uso: disponibles.sh [owner/repo]   (default: el repo del directorio actual)
set -euo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" \
  | jq -s '[.[][] | select(.pull_request | not)]')

# Orden: critica, alta, media, baja, sin prioridad.
ORDEN='def prio: ([.labels[].name | select(startswith("prioridad:"))][0] // "") as $p
  | {"prioridad:critica":0,"prioridad:alta":1,"prioridad:media":2,"prioridad:baja":3}[$p] // 4;
def epica: (.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0);
def etiqueta: ([.labels[].name | select(startswith("prioridad:") or startswith("area:"))] | join(", "));'

echo "## Se pueden empezar ya"
echo
echo "$issues" | jq -r "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) == 0 and (epica | not))] | sort_by(prio, .number)
  | if length == 0 then "_Ninguno._" else .[] | "- #\(.number) \(.title)" + (etiqueta | if . == "" then "" else " — \(.)" end) end'

echo
echo "## Bloqueados"
echo
bloqueados=$(echo "$issues" | jq -r "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) > 0 and (epica | not))] | sort_by(prio, .number) | .[].number')
[ -z "$bloqueados" ] && echo "_Ninguno._"
for n in $bloqueados; do
  titulo=$(echo "$issues" | jq -r ".[] | select(.number == $n) | .title")
  por=$(gh api "repos/$REPO/issues/$n/dependencies/blocked_by" \
    | jq -r '[.[] | select(.state == "open") | "#\(.number)"] | join(", ")')
  echo "- #$n $titulo — bloqueado por $por"
done

echo
echo "## Épicas en curso"
echo
echo "$issues" | jq -r "$ORDEN"'
  [.[] | select(epica)] | sort_by(prio, .number)
  | if length == 0 then "_Ninguna._" else .[] | "- #\(.number) \(.title) — \(.sub_issues_summary.completed)/\(.sub_issues_summary.total) sub-issues cerrados" end'
