#!/usr/bin/env bash
# Junta lo que /mejorar-skills tiene que consolidar: las retros nuevas desde la
# última consolidación y señales objetivas. Solo lee.
# Uso: senales.sh [días]   (default: 30, para las señales objetivas)
set -euo pipefail
DIAS="${1:-30}"
TITULO="Retros del flujo con agentes"
MARCA="<!-- mejorar-skills: consolidado -->"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
cd "$(git rev-parse --show-toplevel)" || exit 1
desde=$(date -u -v-"${DIAS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$DIAS days ago" +%Y-%m-%dT%H:%M:%SZ)

n=$(gh issue list -R "$REPO" --state open --search "\"$TITULO\" in:title" --json number,title \
  -q ".[] | select(.title == \"$TITULO\") | .number" | head -1)
echo "# Señales para mejorar las skills"
echo
echo "## Retros nuevas"
if [ -z "$n" ]; then
  echo "_No existe el issue \"$TITULO\"._"
else
  # Solo las posteriores al último comentario de consolidación.
  # shellcheck disable=SC2016  # programa de jq
  gh api --paginate "repos/$REPO/issues/$n/comments" | jq -rs --arg marca "$MARCA" '
    [.[][]] as $c
    | ([$c | to_entries[] | select(.value.body | contains($marca)) | .key] | max // -1) as $ultima
    | [$c | to_entries[] | select(.key > $ultima) | .value]
    | if length == 0 then "_Ninguna desde la última consolidación._"
      else .[] | "### \(.created_at[:10]) · @\(.user.login) · \(.html_url)\n\(.body)\n" end'
fi

echo
echo "## Fallas de CI en ramas de agentes (últimos $DIAS días)"
gh run list -R "$REPO" --status failure --limit 200 --json headBranch,workflowName,displayTitle,createdAt,url \
  | jq -r --arg desde "$desde" '[.[] | select(.headBranch | startswith("claude/")) | select(.createdAt >= $desde)]
    | if length == 0 then "_Ninguna._" else
      group_by(.workflowName) | sort_by(-length)[]
      | "- **\(.[0].workflowName)**: \(length) falla(s) en \([.[].headBranch] | unique | length) rama(s). Ejemplo: \(.[0].headBranch) — \(.[0].displayTitle) (\(.[0].url))"
    end'

echo
echo "## Reverts (últimos $DIAS días)"
reverts=$(git log --since="$DIAS days ago" -i --grep='^revert' --format='- %h %s (%cr)' 2>/dev/null || true)
echo "${reverts:-_Ninguno._}"
