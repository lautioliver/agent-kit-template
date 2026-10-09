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
# Aislado de la config de git de quien corre los tests (rama por defecto, firma, hooks globales…).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export PATH="$TMP/bin:$PATH" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

git init -q --bare -b main "$TMP/remoto.git"
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
sha=$(cd "$TMP/a" && git log -1 --format=%H -- .claude/skills/implement-issue/SKILL.md)
grep -q "^skill_sha: $sha$" <<<"$c"; afirmar $? "skill_sha es el commit completo del último cambio del SKILL.md"
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
grep -Eq '^[0-9a-f]{40}$' <<<"$punta"; afirmar $? "senales.sh imprime el commit completo para consolidar"
(cd "$TMP/a" && "$AQUI/retro.sh" --consolidado deadbee https://example.test/pull/7 >/dev/null 2>&1); igual $? 64; afirmar $? "--consolidado rechaza un commit que no existe"
(cd "$TMP/a" && "$AQUI/retro.sh" --consolidado "$punta" https://example.test/pull/7 >/dev/null 2>&1) || true
cons=$(git --git-dir="$TMP/remoto.git" show "$RAMA:consolidado.md" 2>/dev/null)
grep -q "^consolidado-hasta: $punta" <<<"$cons" && grep -q "pull/7" <<<"$cons"; afirmar $? "consolidado.md guarda hasta dónde y el PR"
retro b implement-issue 2 "despues" >/dev/null 2>&1 || true
s=$(cd "$TMP/a" && "$AQUI/senales.sh" 2>&1)
grep -q despues <<<"$s" && ! grep -q primera <<<"$s"; afirmar $? "senales.sh después de consolidar muestra solo las nuevas"
grep -q "## Fallas de CI" <<<"$s"; afirmar $? "senales.sh no falla sin gh"

# Ruta relativa desde una subcarpeta del repo.
mkdir -p "$TMP/a/docs"
printf -- '---\nskill: implement-issue\nissue: 3\n---\nrelativa\n' >"$TMP/a/docs/rel.md"
(cd "$TMP/a/docs" && ../.claude/skills/mejorar-skills/retro.sh rel.md >/dev/null 2>&1)
archivos | grep -q 'implement-issue-3\.md$'; afirmar $? "acepta una ruta relativa desde una subcarpeta"

# review-pr sin issue: alcanza con el PR.
printf -- '---\nskill: review-pr\nissue: sin issue\npr: 45\n---\nsin issue\n' >"$TMP/sin.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/sin.md" >/dev/null 2>&1)
archivos | grep -q 'review-pr-pr45\.md$'; afirmar $? "review-pr sin issue usa el número de PR"

# Carrera real: justo antes del push de a, b guarda otra retro. a tiene que reintentar.
real=$(command -v git)
mkdir -p "$TMP/shim"
cat >"$TMP/shim/git" <<SH
#!/usr/bin/env bash
if [ "\$1" = push ] && [ ! -f "$TMP/carrera" ]; then
  touch "$TMP/carrera"
  printf -- '---\nskill: implement-issue\nissue: 8\n---\nintrusa\n' >"$TMP/intrusa.md"
  (cd "$TMP/b" && PATH="$TMP/bin:\${PATH#$TMP/shim:}" "$AQUI/retro.sh" "$TMP/intrusa.md" >/dev/null 2>&1)
fi
exec "$real" "\$@"
SH
chmod +x "$TMP/shim/git"
printf -- '---\nskill: implement-issue\nissue: 9\n---\ncarrera\n' >"$TMP/carrera.md"
err=$(cd "$TMP/a" && PATH="$TMP/shim:$PATH" "$AQUI/retro.sh" "$TMP/carrera.md" 2>&1 >/dev/null)
archivos | grep -q 'implement-issue-8\.md$' && archivos | grep -q 'implement-issue-9\.md$'; afirmar $? "en una carrera se guardan las dos retros"
grep -q reintento <<<"$err"; afirmar $? "en una carrera reintenta"

# Un push que falla por otra razón no se reintenta, muestra el error y deja la retro a mano.
git clone -q "$TMP/remoto.git" "$TMP/c" 2>/dev/null
(cd "$TMP/c" && git remote set-url origin "$TMP/no-existe.git")
err=$(cd "$TMP/c" && "$AQUI/retro.sh" "$TMP/carrera.md" 2>&1 >/dev/null); cod=$?
! igual "$cod" 0 && ! grep -q reintento <<<"$err"; afirmar $? "sin acceso al remoto falla sin reintentar"
grep -q 'no-existe' <<<"$err"; afirmar $? "muestra el error de git"
ls "$TMP/c/.git/retros-pendientes/"*.md >/dev/null 2>&1; afirmar $? "deja la retro en .git/retros-pendientes"

# Sin remoto: guarda en la rama local.
git init -q "$TMP/d"; (cd "$TMP/d" && git commit -q --allow-empty -m base)
(cd "$TMP/d" && "$AQUI/retro.sh" "$TMP/carrera.md" >/dev/null 2>&1)
git -C "$TMP/d" ls-tree -r --name-only "$RAMA" 2>/dev/null | grep -q 'implement-issue-9\.md$'; afirmar $? "sin remoto guarda en la rama local"

# En un repo sin commits la retro no se pierde: se guarda o queda pendiente.
git init -q "$TMP/vacio"
(cd "$TMP/vacio" && "$AQUI/retro.sh" "$TMP/carrera.md" >/dev/null 2>&1)
git -C "$TMP/vacio" ls-tree -r --name-only "$RAMA" 2>/dev/null | grep -q 'implement-issue-9\.md$' \
  || ls "$TMP/vacio/.git/retros-pendientes/"*.md >/dev/null 2>&1; afirmar $? "en un repo sin commits la retro no se pierde"

# Revisión del PR #39.
# --consolidado solo acepta commits de la rama de retros.
otro=$(cd "$TMP/a" && git rev-parse HEAD)
(cd "$TMP/a" && "$AQUI/retro.sh" --consolidado "$otro" https://example.test/pull/8 >/dev/null 2>&1); igual $? 64; afirmar $? "--consolidado rechaza un commit que no es de $RAMA"

# Frontmatter con CRLF y comillas se acepta; sin cerrar se rechaza.
printf -- '---\r\nskill: "implement-issue"\r\nissue: 11\r\n---\r\ncrlf\r\n' >"$TMP/crlf.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/crlf.md" >/dev/null 2>&1)
archivos | grep -q 'implement-issue-11\.md$'; afirmar $? "acepta frontmatter con CRLF y comillas"
printf -- '---\nskill: implement-issue\nissue: 12\nsin cierre\n' >"$TMP/abierto.md"
! (cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/abierto.md" >/dev/null 2>&1); afirmar $? "rechaza un frontmatter sin cerrar"

# Con commit.gpgSign y una firma que falla, igual guarda (la rama de retros no se firma).
(cd "$TMP/a" && git config commit.gpgSign true && git config gpg.program false)
printf -- '---\nskill: implement-issue\nissue: 13\n---\nfirma\n' >"$TMP/firma.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/firma.md" >/dev/null 2>&1)
archivos | grep -q 'implement-issue-13\.md$'; afirmar $? "guarda aunque el repo exija firmar commits"
(cd "$TMP/a" && git config --unset commit.gpgSign && git config --unset gpg.program)

# En un worktree, la pendiente queda en el .git común (sobrevive a git worktree remove).
git -C "$TMP/c" worktree add -q "$TMP/cw" 2>/dev/null
printf -- '---\nskill: implement-issue\nissue: 14\n---\nworktree\n' >"$TMP/wt.md"
(cd "$TMP/cw" && "$AQUI/retro.sh" "$TMP/wt.md" >/dev/null 2>&1)
git -C "$TMP/c" worktree remove --force "$TMP/cw" 2>/dev/null
pend=$(find "$TMP/c/.git/retros-pendientes" -name "*implement-issue-14*.md" 2>/dev/null | head -1)
grep -q . <<<"$pend"; afirmar $? "en un worktree la pendiente sobrevive a git worktree remove"

# Reintentar una pendiente con éxito la borra y no duplica.
(cd "$TMP/c" && git remote set-url origin "$TMP/remoto.git")
(cd "$TMP/c" && "$AQUI/retro.sh" "$pend" >/dev/null 2>&1)
igual "$(archivos | grep -c 'implement-issue-14')" 1; afirmar $? "la pendiente reintentada se guarda una vez"
! [ -e "$pend" ]; afirmar $? "la pendiente reintentada se borra"

# Retros guardadas sin remoto siguen visibles (y se suben) cuando se agrega uno.
git init -q --bare -b main "$TMP/remoto-d.git"
(cd "$TMP/d" && git remote add origin "$TMP/remoto-d.git")
s=$(cd "$TMP/d" && "$AQUI/senales.sh" 2>&1)
grep -q 'implement-issue-9' <<<"$s"; afirmar $? "senales.sh ve las retros locales después de agregar un remoto"
printf -- '---\nskill: implement-issue\nissue: 15\n---\nd\n' >"$TMP/d.md"
(cd "$TMP/d" && "$AQUI/retro.sh" "$TMP/d.md" >/dev/null 2>&1)
git --git-dir="$TMP/remoto-d.git" ls-tree -r --name-only "$RAMA" 2>/dev/null | grep -q 'implement-issue-9'; afirmar $? "al agregar un remoto, las retros locales se suben"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
