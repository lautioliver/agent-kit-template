#!/usr/bin/env bash
# Tests de retro.sh y senales.sh contra un remoto local (no usa GitHub).
# Uso: bash .claude/skills/mejorar-skills/test-retros.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$AQUI/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-retros-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
RAMA=agentes/retros
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
igual() { [ "$1" = "$2" ]; }

# gh falso: los scripts no pueden depender de GitHub para las retros.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 1\n' >"$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

git init -q --bare "$TMP/remoto.git"
clonar() {
  git clone -q "$TMP/remoto.git" "$1" 2>/dev/null
  mkdir -p "$1/.claude/skills"
  cp -R "$RAIZ/.claude/skills/mejorar-skills" "$RAIZ/.claude/skills/implement-issue" "$RAIZ/.claude/skills/review-pr" "$1/.claude/skills/"
}
clonar "$TMP/a"
(cd "$TMP/a" && git add -A && git commit -qm base && git push -q origin HEAD:main 2>/dev/null)
clonar "$TMP/b"; (cd "$TMP/b" && git fetch -q && git reset -q --hard origin/main)

retro() { # retro <clon> <skill> <issue> <texto>
  cat >"$TMP/r.md" <<MD
---
skill: $2
issue: $3
pr: 99
area: docs
rutas: docs/README.md
---
**Desvíos:** $4
MD
  (cd "$TMP/$1" && "$AQUI/retro.sh" "$TMP/r.md")
}
archivos() { git --git-dir="$TMP/remoto.git" ls-tree -r --name-only "$RAMA" -- retros/ 2>/dev/null; }

# 1. Crea un archivo con el frontmatter completo, pushea, y no toca la rama ni el índice.
(cd "$TMP/a" && git switch -q -c claude/1-algo && echo x >sucio.txt && git add sucio.txt)
retro a implement-issue 1 "primera" >/dev/null 2>"$TMP/err" || true
igual "$(archivos | wc -l | tr -d " ")" 1; afirmar $? "retro.sh pushea un archivo a $RAMA"
f=$(archivos | head -1)
grep -Eq '^retros/[0-9]{4}-[0-9]{2}-[0-9]{2}-implement-issue-1\.md$' <<<"$f"; afirmar $? "el nombre es AAAA-MM-DD-<skill>-<n>.md"
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$f" 2>/dev/null)
for campo in skill issue pr area rutas skill_sha fecha; do
  grep -Eq "^$campo: .+" <<<"$c"; afirmar $? "el frontmatter tiene $campo"
done
sha=$(cd "$TMP/a" && git log -1 --format=%h -- .claude/skills/implement-issue/SKILL.md)
grep -q "^skill_sha: $sha" <<<"$c"; afirmar $? "skill_sha es el último commit del SKILL.md"
igual "$(cd "$TMP/a" && git branch --show-current)" claude/1-algo; afirmar $? "la rama actual no cambió"
igual "$(cd "$TMP/a" && git diff --cached --name-only)" sucio.txt; afirmar $? "el índice no cambió"

# Sin frontmatter obligatorio, no publica.
printf '**Desvíos:** nada\n' >"$TMP/mal.md"
! (cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/mal.md" >/dev/null 2>&1); afirmar $? "rechaza una retro sin skill ni issue"

# 2. Dos retros desde clones desactualizados (y la misma skill e issue el mismo día) no se pisan.
retro b review-pr 1 "desde b" >/dev/null 2>&1 || true
retro a review-pr 1 "desde a" >/dev/null 2>&1 || true
igual "$(archivos | wc -l | tr -d " ")" 3; afirmar $? "tres retros en el remoto"

# 3 y 4. senales.sh muestra solo lo posterior a consolidado.md.
s=$(cd "$TMP/a" && "$AQUI/senales.sh" 2>&1)
grep -q primera <<<"$s" && grep -q "desde a" <<<"$s" && grep -q "desde b" <<<"$s"; afirmar $? "senales.sh sin consolidar muestra todas"
punta=$(sed -n 's/.*consolidar hasta: \([0-9a-f]\{7,\}\).*/\1/p' <<<"$s" | head -1)
grep -q . <<<"$punta"; afirmar $? "senales.sh imprime la punta para consolidar"
(cd "$TMP/a" && "$AQUI/retro.sh" --consolidado "$punta" https://example.test/pull/7 >/dev/null 2>&1) || true
cons=$(git --git-dir="$TMP/remoto.git" show "$RAMA:consolidado.md" 2>/dev/null)
grep -q "^consolidado-hasta: $punta" <<<"$cons" && grep -q "pull/7" <<<"$cons"; afirmar $? "consolidado.md guarda hasta dónde y el PR"
retro b implement-issue 2 "despues" >/dev/null 2>&1 || true
s=$(cd "$TMP/a" && "$AQUI/senales.sh" 2>&1)
grep -q despues <<<"$s" && ! grep -q primera <<<"$s"; afirmar $? "senales.sh después de consolidar muestra solo las nuevas"
grep -q "## Fallas de CI" <<<"$s"; afirmar $? "senales.sh no falla sin gh"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
