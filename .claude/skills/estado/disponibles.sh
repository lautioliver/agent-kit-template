#!/usr/bin/env bash
# Lista los issues abiertos que se pueden empezar ya (sin bloqueantes abiertos),
# ordenados por prioridad y con los del usuario actual primero; aparte los que
# ya tienen un PR abierto que los cierra (en curso), los
# bloqueados con lo que los bloquea, y las épicas (issues con sub-issues
# abiertos), que se trabajan por sus sub-issues.
# Solo lee: no modifica nada.
# Uso: disponibles.sh [owner/repo]   (default: el repo del directorio actual)
set -euo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
YO=$(gh api user -q .login 2>/dev/null || true)

issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" \
  | jq -s '[.[][] | select(.pull_request | not)]')

# PRs abiertos y qué issues cierran: {"<n° issue>": [<n° PR>, ...]}.
# GitHub solo llena closingIssuesReferences cuando el PR va a la rama por defecto,
# así que también se lee "Closes #n" del cuerpo y el número de la rama (<tipo>/<n>-…).
# shellcheck disable=SC2016  # programa de jq
MAPEO='
  [.[] | . as $pr
    | ([.closingIssuesReferences[].number]
       + ([(.body // "") | gsub("`[^`]*`"; "") | scan("(?i)(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):? +#([0-9]+)") | .[0] | tonumber])
       + ([.headRefName | capture("^[a-z]+/(?<n>[0-9]+)-")? | .n | tonumber]))
    | unique[] | {issue: tostring, pr: $pr.number}]
  | group_by(.issue) | map({key: .[0].issue, value: [.[].pr]}) | from_entries'
CAMPOS=number,headRefName,body,closingIssuesReferences,baseRefName
prs=$(gh pr list -R "$REPO" --state open --limit 200 --json "$CAMPOS" | jq "$MAPEO")
# Mergeados a una rama que no es la principal (p. ej. develop): el issue sigue abierto
# hasta el release, pero ya está resuelto. No se ofrece como disponible.
PRINCIPAL=$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name)
release=$(gh pr list -R "$REPO" --state merged --limit 200 --json "$CAMPOS" \
  | jq --arg p "$PRINCIPAL" "[.[] | select(.baseRefName != \$p)] | $MAPEO")

# Orden: critica, alta, media, baja, sin prioridad.
# shellcheck disable=SC2016  # programa de jq: los $ son de jq, no de bash
ORDEN='def prio: ([.labels[].name | select(startswith("prioridad:"))][0] // "") as $p
  | {"prioridad:critica":0,"prioridad:alta":1,"prioridad:media":2,"prioridad:baja":3}[$p] // 4;
def epica: (.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0);
def prs: $prs[.number | tostring] // [];
# Asignado = responsable (lo pone crear-issue según .github/equipo.json); en curso = con PR abierto.
def enrelease: ($release[.number | tostring] // []) | length > 0;
def tomado: (prs | length) > 0 or enrelease;
def mio: any(.assignees[]; .login == $yo);
def responsable: if (.assignees | length) == 0 then "sin responsable" else ([.assignees[].login | "@" + .] | join(", ")) end;
def quien: ([.assignees[].login | "@" + .] + [prs[] | "PR #\(.)"]) | join(", ");
def etiqueta: ([.labels[].name | select(startswith("prioridad:") or startswith("area:"))] | join(", "));'

echo "## Se pueden empezar ya"
echo
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) == 0 and (epica | not) and (tomado | not))]
  | sort_by((if mio then 0 else 1 end), prio, .number)
  | if length == 0 then "_Ninguno._" else .[] | "- #\(.number) \(.title) — \(responsable)" + (etiqueta | if . == "" then "" else " · \(.)" end) end'

echo
echo "## En curso"
echo
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) == 0 and (epica | not) and (prs | length) > 0)] | sort_by(prio, .number)
  | if length == 0 then "_Ninguno._" else .[] | "- #\(.number) \(.title) — \(quien)" end'

echo
echo "## Esperando release"
echo
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select(enrelease and ((prs | length) == 0))] | sort_by(.number)
  | if length == 0 then "_Ninguno._" else .[] | ($release[.number | tostring]) as $r | "- #\(.number) \(.title) — mergeado en \(if ($r | length) > 1 then "los PRs" else "el PR" end) #\($r | map(tostring) | join(", #")); falta pasar a la rama principal" end'

echo
echo "## Bloqueados"
echo
bloqueados=$(echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
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
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select(epica)] | sort_by(prio, .number)
  | if length == 0 then "_Ninguna._" else .[] | "- #\(.number) \(.title) — \(.sub_issues_summary.completed)/\(.sub_issues_summary.total) sub-issues cerrados" end'
