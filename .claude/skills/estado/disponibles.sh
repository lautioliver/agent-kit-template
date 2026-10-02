#!/usr/bin/env bash
# Lista los issues abiertos que se pueden empezar ya (sin bloqueantes abiertos),
# ordenados por prioridad; aparte los que ya tomó alguien (asignados o con un
# PR abierto que los cierra), los
# bloqueados con lo que los bloquea, y las épicas (issues con sub-issues
# abiertos), que se trabajan por sus sub-issues.
# Solo lee: no modifica nada.
# Uso: disponibles.sh [owner/repo]   (default: el repo del directorio actual)
set -euo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" \
  | jq -s '[.[][] | select(.pull_request | not)]')

# PRs abiertos y qué issues cierran: {"<n° issue>": [<n° PR>, ...]}.
# GitHub solo llena closingIssuesReferences cuando el PR va a la rama por defecto,
# así que también se lee "Closes #n" del cuerpo y el número de la rama (<tipo>/<n>-…).
# shellcheck disable=SC2016  # programa de jq
prs=$(gh pr list -R "$REPO" --state open --limit 200 --json number,headRefName,body,closingIssuesReferences | jq '
  [.[] | . as $pr
    | ([.closingIssuesReferences[].number]
       + ([(.body // "") | scan("(?i)(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):? +#([0-9]+)") | .[0] | tonumber])
       + ([.headRefName | capture("^[a-z]+/(?<n>[0-9]+)-")? | .n | tonumber]))
    | unique[] | {issue: tostring, pr: $pr.number}]
  | group_by(.issue) | map({key: .[0].issue, value: [.[].pr]}) | from_entries')

# Orden: critica, alta, media, baja, sin prioridad.
# shellcheck disable=SC2016  # programa de jq: los $ son de jq, no de bash
ORDEN='def prio: ([.labels[].name | select(startswith("prioridad:"))][0] // "") as $p
  | {"prioridad:critica":0,"prioridad:alta":1,"prioridad:media":2,"prioridad:baja":3}[$p] // 4;
def epica: (.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0);
def prs: $prs[.number | tostring] // [];
def tomado: (.assignees | length) > 0 or (prs | length) > 0;
def quien: ([.assignees[].login | "@" + .] + [prs[] | "PR #\(.)"]) | join(", ");
def etiqueta: ([.labels[].name | select(startswith("prioridad:") or startswith("area:"))] | join(", "));'

echo "## Se pueden empezar ya"
echo
echo "$issues" | jq -r --argjson prs "$prs" "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) == 0 and (epica | not) and (tomado | not))] | sort_by(prio, .number)
  | if length == 0 then "_Ninguno._" else .[] | "- #\(.number) \(.title)" + (etiqueta | if . == "" then "" else " — \(.)" end) end'

echo
echo "## En curso"
echo
echo "$issues" | jq -r --argjson prs "$prs" "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) == 0 and (epica | not) and tomado)] | sort_by(prio, .number)
  | if length == 0 then "_Ninguno._" else .[] | "- #\(.number) \(.title) — \(quien)" end'

echo
echo "## Bloqueados"
echo
bloqueados=$(echo "$issues" | jq -r --argjson prs "$prs" "$ORDEN"'
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
echo "$issues" | jq -r --argjson prs "$prs" "$ORDEN"'
  [.[] | select(epica)] | sort_by(prio, .number)
  | if length == 0 then "_Ninguna._" else .[] | "- #\(.number) \(.title) — \(.sub_issues_summary.completed)/\(.sub_issues_summary.total) sub-issues cerrados" end'
