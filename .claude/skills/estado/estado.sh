#!/usr/bin/env bash
# Resumen del estado actual del proyecto, generado en el momento desde las fuentes
# (git, GitHub, docs). No se guarda: siempre está al día. Solo lee.
# Uso: estado.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
REPO=$(gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner')
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch -q --tags origin 2>/dev/null || true

echo "# Estado de $REPO — $(date +%Y-%m-%d)"
echo
echo "## Versión y ramas"
echo "- Última versión: $(git describe --tags --abbrev=0 "origin/$DEFAULT" 2>/dev/null || echo 'sin tags')"
echo "- Rama por defecto: $DEFAULT"
regla=$(grep -m1 '^\- \*\*Rama base:\*\*' AGENTS.md 2>/dev/null | sed 's/^- \*\*Rama base:\*\* //')
[ -n "$regla" ] && echo "- Flujo: $regla"
rel=$(git branch -r --list 'origin/release/*' | sed 's#origin/##' | xargs)
[ -n "$rel" ] && echo "- Releases abiertas: $rel"
echo "- Último commit en $DEFAULT: $(git log -1 --format='%h %s (%cr)' "origin/$DEFAULT" 2>/dev/null)"

echo
echo "## Arquitectura"
if grep -q "TODO: completar" docs/development/architecture.md 2>/dev/null; then
  echo "_docs/development/architecture.md todavía no tiene contenido._"
else
  echo "Ver docs/development/architecture.md (actualizado $(git log -1 --format=%cr -- docs/development/architecture.md))."
fi

echo
echo "## Trabajo"
gh api "repos/$REPO/issues?state=open&per_page=100" --paginate 2>/dev/null | jq -rs '
  [.[][] | select(.pull_request | not)] as $i
  | "- Issues abiertos: \($i | length) · bloqueados: \([$i[] | select((.issue_dependencies_summary.blocked_by // 0) > 0)] | length) · asignados: \([$i[] | select(.assignees | length > 0)] | length) · sin triar: \([$i[] | select(any(.labels[]; .name == "estado:a-triar"))] | length)",
    ([$i[] | select((.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0))][]
      | "- Épica #\(.number) \(.title): \(.sub_issues_summary.completed)/\(.sub_issues_summary.total)")'
echo "- PRs abiertos:"
gh pr list --limit 20 --json number,title,headRefName,isDraft -q '.[] | "  - #\(.number) \(.title)\(if .isDraft then " (draft)" else "" end)"' | grep . || echo "  _Ninguno._"

echo
echo "## Deuda conocida"
gh issue list --state open --label "tipo:audit" --limit 100 --json number -q 'length' 2>/dev/null \
  | xargs -I{} echo "- Hallazgos de auditoría abiertos: {}"
gh issue list --state open --label "prioridad:critica" --limit 20 --json number,title -q '.[] | "- CRÍTICO #\(.number) \(.title)"'

echo
echo "## Decisiones recientes"
recientes=$(git log --since="60 days ago" --diff-filter=AM --name-only --format= "origin/$DEFAULT" -- 'docs/decisions/ADR-*.md' 2>/dev/null | sort -u | grep -v ADR-000)
if [ -z "$recientes" ]; then echo "_Ningún ADR nuevo o enmendado en 60 días._"; else
  for f in $recientes; do [ -f "$f" ] && echo "- $(head -1 "$f" | sed 's/^# //') ($(git log -1 --format=%cr -- "$f"))"; done
fi

echo
echo "## Migraciones"
migr=$(python3 -c "import json;print(' '.join(r for s in json.load(open('docs/mapa-agentes.json'))['sensibles'] if s['tipo']=='schema' for r in s['rutas']))" 2>/dev/null)
pend=""
for pr in $(gh pr list --limit 50 --json number -q '.[].number'); do
  files=$(gh pr diff "$pr" --name-only 2>/dev/null)
  for g in $migr; do
    re=$(printf '%s' "$g" | sed 's#\*\*/#(.*/)?#g; s#\*\*#.*#g; s#\*#[^/]*#g')
    echo "$files" | grep -Eq "^$re$" && { pend="$pend #$pr"; break; }
  done
done
if [ -n "$pend" ]; then echo "- PRs abiertos con cambios de schema:$pend"; else echo "_Ningún PR abierto toca migraciones._"; fi
