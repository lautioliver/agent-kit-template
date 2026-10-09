#!/usr/bin/env bash
# Junta lo que /mejorar-skills tiene que consolidar: las retros nuevas desde la
# última consolidación (rama agentes/retros, solo git) y señales objetivas
# (fallas de CI y reverts; las de CI necesitan gh). Solo lee.
# Uso: senales.sh [días]   (default: 30, para las señales objetivas)
set -euo pipefail
DIAS="${1:-30}"
RAMA=agentes/retros
cd "$(git rev-parse --show-toplevel)" || exit 1
desde=$(date -u -v-"${DIAS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$DIAS days ago" +%Y-%m-%dT%H:%M:%SZ)

# La del remoto si existe; si no, la local (retros guardadas antes de tener remoto).
ref="refs/heads/$RAMA"
if git remote get-url origin >/dev/null 2>&1; then
  git fetch -q origin "+$ref:refs/remotes/origin/$RAMA" 2>/dev/null || true
  git rev-parse -q --verify "refs/remotes/origin/$RAMA" >/dev/null && ref="refs/remotes/origin/$RAMA"
fi
echo "# Señales para mejorar las skills"
echo
echo "## Retros nuevas"
if ! punta=$(git rev-parse -q --verify "$ref"); then
  echo "_Todavía no hay retros (no existe la rama $RAMA)._"
else
  hasta=$(git show "$punta:consolidado.md" 2>/dev/null | sed -n 's/^consolidado-hasta: *//p' | head -1 || true)
  if [ -n "$hasta" ] && git merge-base --is-ancestor "$hasta" "$punta" 2>/dev/null; then
    nuevas=$(git diff --name-only --diff-filter=A "$hasta" "$punta" -- retros/)
  else
    [ -n "$hasta" ] && echo "_Aviso: consolidado.md apunta a $hasta, que no está en $RAMA; muestro todas las retros._"
    nuevas=$(git ls-tree -r --name-only "$punta" -- retros/)
  fi
  if [ -z "$nuevas" ]; then
    echo "_Ninguna desde la última consolidación._"
  else
    while IFS= read -r f; do
      echo "### $f"; git show "$punta:$f"; echo
    done <<<"$nuevas"
  fi
  echo "Para marcar esto como consolidado, consolidar hasta: $punta"
fi

echo
echo "## Fallas de CI en ramas de agentes (últimos $DIAS días)"
if REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); then
  gh run list -R "$REPO" --status failure --limit 200 --json headBranch,workflowName,displayTitle,createdAt,url \
    | jq -r --arg desde "$desde" '[.[] | select(.headBranch | startswith("claude/")) | select(.createdAt >= $desde)]
      | if length == 0 then "_Ninguna._" else
        group_by(.workflowName) | sort_by(-length)[]
        | "- **\(.[0].workflowName)**: \(length) falla(s) en \([.[].headBranch] | unique | length) rama(s). Ejemplo: \(.[0].headBranch) — \(.[0].displayTitle) (\(.[0].url))"
      end'
else
  echo "_No disponible: hace falta gh autenticado._"
fi

echo
echo "## Reverts (últimos $DIAS días)"
reverts=$(git log --since="$DIAS days ago" -i --grep='^revert' --format='- %h %s (%cr)' 2>/dev/null || true)
echo "${reverts:-_Ninguno._}"
