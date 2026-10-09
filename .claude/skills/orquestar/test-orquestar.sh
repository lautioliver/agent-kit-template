#!/usr/bin/env bash
# Tests de ruteo.py y limpiar.sh con un gh falso y un repo local (no usa GitHub).
# Uso: bash .claude/skills/orquestar/test-orquestar.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$AQUI/../../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-orquestar-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

# gh falso: cada issue es un JSON en $GH_ISSUES/<n>.json.
mkdir -p "$TMP/bin" "$TMP/issues"
export GH_ISSUES="$TMP/issues"
cat >"$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "repo view"*) echo o/r ;;
  api\ repos/o/r/issues/*) f="$GH_ISSUES/${2##*/}.json"; [ -f "$f" ] && cat "$f" || exit 1 ;;
  "pr list --head "*) f="$GH_ISSUES/pr-${4//\//_}.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
  *) echo "gh falso: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
issue() { # issue <n> <estado> <labels separados por coma> <cuerpo>
  python3 - "$@" >"$TMP/issues/$1.json" <<'PY'
import json, sys
n, estado, labels, cuerpo = sys.argv[1:5]
print(json.dumps({"number": int(n), "state": estado, "title": f"Issue {n}",
                  "labels": [{"name": l} for l in labels.split(",") if l], "body": cuerpo}))
PY
}

# Proyecto con un mapa que marca src/auth/** y src/pagos/** como sensibles.
P="$TMP/proj"
mkdir -p "$P/docs"
git init -q -b main "$P"
printf '{"sensibles": [{"tipo": "auth", "rutas": ["src/auth/**"]}, {"tipo": "dinero", "rutas": ["?src/pagos/**"]}, {"tipo": "dependencias", "rutas": ["?package.json", "?*.lock"]}, {"tipo": "infra", "rutas": ["?Dockerfile"]}]}\n' >"$P/docs/mapa-agentes.json"
mkdir -p "$P/scripts"; cp -R "$RAIZ/scripts/agentes" "$P/scripts/"
(cd "$P" && git add -A && git commit -qm base)

ruteo() { (cd "$P" && python3 "$AQUI/ruteo.py" "$1" 2>&1); }

# 1. Regla de ruteo (decisión 2 de la épica #33).
issue 1 open "tipo:docs,area:docs" "Corregir un link del README."
s=$(ruteo 1); es "$(head -1 <<<"$s")" = haiku; afirmar $? "tipo:docs sin riesgo → haiku"
issue 2 open "tipo:task" "Ordenar los scripts."
s=$(ruteo 2); es "$(head -1 <<<"$s")" = haiku; afirmar $? "tipo:task sin riesgo → haiku"
issue 3 open "tipo:bug" "Arreglar el contador."
s=$(ruteo 3); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "tipo:bug → sonnet"
grep -q "tipo:bug" <<<"$s"; afirmar $? "el motivo nombra el tipo"
issue 4 open "tipo:feature" "Algo nuevo."
s=$(ruteo 4); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "tipo:feature → sonnet"
issue 5 open "tipo:docs,logica-negocio" "Aclarar la regla de reembolsos."
s=$(ruteo 5); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "logica-negocio → sonnet aunque sea tipo:docs"
issue 6 open "tipo:task,breaking-change" "Renombrar un campo."
s=$(ruteo 6); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "breaking-change → sonnet aunque sea tipo:task"
issue 7 open "tipo:task" "Ordenar \`src/auth/sesion.ts\` y sus tests."
s=$(ruteo 7); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "una ruta sensible nombrada en el texto → sonnet"
grep -q "src/auth/sesion.ts" <<<"$s" && grep -q "auth" <<<"$s"; afirmar $? "el motivo nombra la ruta y el tipo sensible"
issue 8 open "tipo:docs" "Documentar la carpeta src/pagos/ (sin tocar código)."
s=$(ruteo 8); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "una carpeta sensible sin backticks también cuenta"
issue 9 open "" "Sin labels."
s=$(ruteo 9); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "sin tipo: → sonnet"
issue 20 open "tipo:task" "Actualizar lodash en package.json."
s=$(ruteo 20); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "una ruta sensible sin barra (package.json) → sonnet"
issue 21 open "tipo:task" "Ajustar el Dockerfile."
s=$(ruteo 21); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "Dockerfile nombrado → sonnet"
issue 22 open "tipo:task" "Regenerar yarn.lock."
s=$(ruteo 22); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "un archivo que coincide con *.lock → sonnet"
issue 23 open "tipo:docs" "Documentar la carpeta src/auth"
s=$(ruteo 23); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "una carpeta sensible sin barra final → sonnet"
issue 24 open "tipo:bug,tipo:docs" "Doble tipo."
s=$(ruteo 24); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "con un tipo: pesado además del liviano → sonnet"
issue 26 open "tipo:task" "Revisar ./src/auth/sesion.ts"
s=$(ruteo 26); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "una ruta sensible con ./ adelante → sonnet"
issue 27 open "tipo:docs" "Ver https://github.com/o/r/blob/main/src/auth/sesion.ts"
s=$(ruteo 27); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "una ruta sensible dentro de un link → sonnet"
issue 28 open "tipo:task" "Ajustar el dockerfile."
s=$(ruteo 28); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "una ruta sensible en minúscula (dockerfile) → sonnet"
issue 25 open "tipo:docs" "Explicar el package manager y la arquitectura."
s=$(ruteo 25); es "$(head -1 <<<"$s")" = haiku; afirmar $? "palabras sueltas que no son rutas sensibles no cambian el ruteo"
mkdir -p "$TMP/sin-repo"; printf '#!/bin/sh\necho "no git remotes found" >&2; exit 1\n' >"$TMP/sin-repo/gh"; chmod +x "$TMP/sin-repo/gh"
s=$(cd "$P" && PATH="$TMP/sin-repo:$PATH" python3 "$AQUI/ruteo.py" 1 2>&1); c=$?
! es "$c" -eq 0 && grep -qi "repo" <<<"$s"; afirmar $? "si gh no encuentra el repo, lo dice (no un 404 del issue)"
mv "$P/docs/mapa-agentes.json" "$TMP/mapa.json"
s=$(ruteo 1); es "$(head -1 <<<"$s")" = sonnet; afirmar $? "sin mapa no se pueden descartar rutas sensibles → sonnet"
mv "$TMP/mapa.json" "$P/docs/mapa-agentes.json"
(cd "$P" && python3 "$AQUI/ruteo.py" 999 >/dev/null 2>&1); c=$?
! es "$c" -eq 0; afirmar $? "un issue que no existe sale con error"

# 2. limpiar.sh: worktrees de issues cerrados, sin pisar trabajo ni retros pendientes.
WT="$TMP/proj-wt"
for n in 10 11 12 13; do git -C "$P" worktree add -q -b "claude/$n-x" "$WT/$n" 2>/dev/null; done
issue 10 closed "tipo:task" "Cerrado y limpio."
issue 11 open "tipo:task" "Abierto."
issue 12 closed "tipo:task" "Cerrado con cambios sin commitear."
issue 13 closed "tipo:task" "Cerrado y limpio, el segundo."
echo sucio >"$WT/12/sucio.txt"

s=$(cd "$P" && "$AQUI/limpiar.sh" 2>&1); c=$?
afirmar $c "limpiar.sh sin --borrar termina bien"
grep -q "$WT/10" <<<"$s" && grep -q "$WT/13" <<<"$s"; afirmar $? "lista los worktrees de issues cerrados"
! grep -q "$WT/11" <<<"$s"; afirmar $? "no lista los de issues abiertos"
grep -q "$WT/12.*sin commitear" <<<"$s"; afirmar $? "avisa que el de #12 tiene cambios sin commitear"
es -d "$WT/10"; afirmar $? "sin --borrar no borra nada"

# Con una retro pendiente no borra ninguno.
mkdir -p "$P/.git/retros-pendientes"; echo r >"$P/.git/retros-pendientes/x.md"
s=$(cd "$P" && "$AQUI/limpiar.sh" --borrar 2>&1); c=$?
! es "$c" -eq 0 && es -d "$WT/10" && grep -q "retros-pendientes" <<<"$s"; afirmar $? "con retros pendientes no borra y dice por qué"
rm -rf "$P/.git/retros-pendientes"

# Si no puede leer un issue, no lo da por "nada que limpiar": lo dice y sale con error.
mkdir -p "$WT"; git -C "$P" worktree add -q -b claude/14-x "$WT/14" 2>/dev/null
s=$(cd "$P" && "$AQUI/limpiar.sh" 2>&1); c=$?
! es "$c" -eq 0 && grep -q "#14" <<<"$s"; afirmar $? "si no puede leer el estado de un issue, lo dice y sale con error"
git -C "$P" worktree remove "$WT/14"; git -C "$P" branch -q -D claude/14-x

# Un worktree que no se puede borrar (bloqueado) se reporta y el script sale con error.
git -C "$P" worktree lock "$WT/13"
s=$(cd "$P" && "$AQUI/limpiar.sh" --borrar 2>&1); c=$?
! es "$c" -eq 0 && grep -q "no se pudo borrar.*$WT/13" <<<"$s" && ! es -d "$WT/10"; afirmar $? "un worktree que no se puede borrar se reporta, y los demás se borran"
git -C "$P" worktree unlock "$WT/13"

s=$(cd "$P" && "$AQUI/limpiar.sh" --borrar 2>&1); c=$?
afirmar $c "limpiar.sh --borrar termina bien"

# Ramas de issues cerrados: se decide por el estado del PR en GitHub (sirve con squash y rebase).
# limpiar.sh solo las lista, sin fetch: borrar una rama (local o remota) lo decide la persona.
git init -q --bare -b main "$TMP/remoto.git"; git -C "$P" remote add origin "$TMP/remoto.git"
git -C "$P" push -q origin main 2>/dev/null; git -C "$P" remote set-head origin main
pr() { printf '[{"number": %s, "state": "%s"}]\n' "$2" "$3" >"$TMP/issues/pr-claude_$1-x.json"; } # pr <n> <pr> <estado>
for n in 15 16 17 18 19 20; do git -C "$P" branch "claude/$n-x" main; (cd "$P" && git switch -q "claude/$n-x" && git commit -q --allow-empty -m "r$n" && git push -q origin "claude/$n-x" 2>/dev/null && git switch -q main); done
(cd "$P" && git switch -q claude/19-x && git commit -q --allow-empty -m "sin pushear" && git switch -q main)
git -C "$P" branch -q -D claude/20-x   # solo existe en el remoto
for n in 15 16 18 19 20; do issue "$n" closed "tipo:task" "Cerrado."; done; issue 17 open "tipo:task" "Abierto."
pr 15 115 CLOSED; pr 16 116 MERGED; pr 17 117 OPEN; pr 19 119 CLOSED; pr 20 120 CLOSED   # 18: sin PR
antes=$(git -C "$P" for-each-ref --format='%(refname) %(objectname)' refs/remotes)
s=$(cd "$P" && "$AQUI/limpiar.sh" 2>&1)
grep -q "claude/15-x.*cerrado sin mergear" <<<"$s" && grep -q "claude/20-x.*cerrado sin mergear" <<<"$s"; afirmar $? "lista las ramas de PRs cerrados sin mergear, también las que solo están en el remoto"
! grep -q "claude/16-x" <<<"$s" && ! grep -q "claude/17-x" <<<"$s"; afirmar $? "no lista la de un PR mergeado (aunque sea squash) ni la de un issue abierto"
grep -q "claude/18-x.*sin PR" <<<"$s" && grep -q "claude/19-x.*sin pushear" <<<"$s"; afirmar $? "avisa de la rama sin PR y de la que tiene commits sin pushear"
grep -q "git push origin --delete" <<<"$s"; afirmar $? "dice cómo borrar las ramas a mano (sin gh --delete-branch)"
es "$(git -C "$P" for-each-ref --format='%(refname) %(objectname)' refs/remotes)" = "$antes"; afirmar $? "listar no hace fetch ni toca las refs remotas"
(cd "$P" && "$AQUI/limpiar.sh" --borrar >/dev/null 2>&1)
git -C "$P" rev-parse -q --verify claude/15-x >/dev/null && git --git-dir="$TMP/remoto.git" rev-parse -q --verify claude/15-x >/dev/null && git --git-dir="$TMP/remoto.git" rev-parse -q --verify claude/20-x >/dev/null; afirmar $? "--borrar no borra ramas (ni locales ni remotas): eso lo decide la persona"
! es -d "$WT/10" && ! es -d "$WT/13"; afirmar $? "--borrar borra los worktrees limpios de issues cerrados"
es -d "$WT/11" && es -f "$WT/12/sucio.txt"; afirmar $? "--borrar no toca el abierto ni el que tiene cambios"
git -C "$P" rev-parse -q --verify claude/10-x >/dev/null; afirmar $? "--borrar deja la rama (solo saca el worktree)"

# Una rama de PR cerrado que todavía tiene worktree: git branch -D falla hasta sacarlo, así que
# los comandos para borrar ramas salen después de sacar los worktrees, y sin --borrar lo avisa.
git -C "$P" worktree add -q -b claude/21-x "$WT/21" main 2>/dev/null
(cd "$WT/21" && git commit -q --allow-empty -m r21 && git push -q origin claude/21-x 2>/dev/null)
issue 21 closed "tipo:task" "Cerrado."; pr 21 121 CLOSED
s=$(cd "$P" && "$AQUI/limpiar.sh" 2>&1)
grep -q "claude/21-x.*--borrar" <<<"$s"; afirmar $? "sin --borrar avisa que la rama con worktree se borra después de --borrar"
grep -q "git push origin --delete claude/15-x" <<<"$s"; afirmar $? "da el comando concreto de cada rama"
s=$(cd "$P" && "$AQUI/limpiar.sh" --borrar 2>&1)
b=$(grep -n "Borrado: $WT/21" <<<"$s" | cut -d: -f1); d=$(grep -n "git branch -D claude/21-x" <<<"$s" | cut -d: -f1)
es -n "$b" && es -n "$d" && es "$d" -gt "$b"; afirmar $? "--borrar da los comandos de las ramas después de sacar los worktrees"
(cd "$P" && eval "$(grep "git branch -D claude/21-x" <<<"$s")" >/dev/null 2>&1) && ! git -C "$P" rev-parse -q --verify claude/21-x >/dev/null; afirmar $? "el comando que da limpiar.sh borra la rama (ya sin worktree)"

# 3. Lo que hace falta para correr en paralelo (criterios de #37).
! grep -q 'push -u' "$RAIZ/.claude/skills/implement-issue/SKILL.md"; afirmar $? "implement-issue pushea sin -u (el -u escribe .git/config y choca en paralelo)"
! grep -Eq 'pushe[aá] de nuevo[^`]*$' "$RAIZ/.claude/skills/implement-issue/SKILL.md" && grep -q 'git push origin HEAD' "$RAIZ/.claude/agents/implementador.md"; afirmar $? "cada push dice git push origin HEAD (la rama no tiene upstream)"
M="$RAIZ/docs/mapa-agentes.json"
for f in .claude/skills/implement-issue/SKILL.md .gitignore perfiles/chico/BORRAR; do
  python3 -c "import json,sys; v=[x for x in json.load(open('$M'))['verificar'] if x['nombre']=='orquestar'][0]; sys.exit(0 if any(g.lstrip('?')=='$f' for g in v['cuando']) else 1)"
  afirmar $? "la verificación orquestar del mapa corre cuando cambia $f"
done
R="$RAIZ/.claude/agents/revisor.md"
grep -q 'refs/revision/<pr>-<sufijo>' "$R" && grep -q -- '-revision-<pr>-<sufijo>' "$R"; afirmar $? "revisor: ref y worktree con sufijo único (dos revisiones del mismo PR no chocan)"
! grep -q 'retro[^.]*desde el checkout principal' "$R" "$RAIZ/docs/agentes/contrato-subagentes.md"; afirmar $? "la retro del revisor no depende del checkout principal del repo (podía estar en una rama vieja)"
grep -q 'checkout del orquestador.*retro.sh' "$R" && ! grep -q 'worktree de revisión.*retro.sh' "$R"; afirmar $? "revisor: corre el retro.sh del checkout del orquestador, no el del PR (no revisado)"
grep -q 'skill_sha' "$R" && grep -q 'skill_sha' "$AQUI/SKILL.md"; afirmar $? "orquestar le pasa skill_sha al revisor (la versión de review-pr que corrió)"
for a in implementador implementador-liviano; do
  grep -q 'skill_sha' "$RAIZ/.claude/agents/$a.md"; afirmar $? "$a: escribe en la retro el skill_sha que le pasa el orquestador"
done
grep -qi 'frená.*\.claude\|\.claude.*frená' "$AQUI/SKILL.md"; afirmar $? "orquestar frena si su checkout tiene cambios en .claude/"
grep -q 'revisor.*agente_sha\|agente_sha.*revisor' "$AQUI/SKILL.md" && grep -q 'checkout del orquestador' "$AQUI/SKILL.md"; afirmar $? "orquestar le pasa al revisor agente_sha y el checkout del orquestador"
for a in implementador implementador-liviano revisor; do
  grep -q 'agente_sha' "$RAIZ/.claude/agents/$a.md"; afirmar $? "$a: escribe en la retro el agente_sha que le pasa el orquestador"
done
grep -q 'agente_sha' "$AQUI/SKILL.md"; afirmar $? "orquestar le pasa agente_sha a cada subagente"
grep -qi 'markdown crudo' "$R"; afirmar $? "revisor: el texto de la revisión va en Markdown crudo, sin entidades HTML"
grep -qi 'relanzado.*consulta\|consulta.*relanzado' "$AQUI/SKILL.md"; afirmar $? "orquestar: dice qué hacer si un relanzado devuelve consulta"
C="$RAIZ/docs/agentes/contrato-subagentes.md"; I="$RAIZ/.claude/skills/implement-issue/SKILL.md"
grep -qi 'markdown crudo' "$C"; afirmar $? "contrato: todo texto para GitHub va en Markdown crudo (también el de los implementadores)"
grep -q '^autorevision:' "$C" && grep -q 'autorevision' "$AQUI/SKILL.md"; afirmar $? "contrato: la salida dice si hubo /code-review, y orquestar lo informa"
! grep -qi "si está disponible el comando \`/code-review\`" "$I" && grep -qi 'code-review.*obligatori' "$I"; afirmar $? "implement-issue: /code-review es obligatorio"
grep -qi 'que el issue lo pida no es la aprobación' "$I" && grep -qi 'que el issue lo pida no es la aprobación' "$C"; afirmar $? "un issue que pide tocar algo de consultar no es la aprobación"
grep -qi 'que el issue lo pida no es la aprobación' "$RAIZ/AGENTS.md"; afirmar $? "AGENTS.md: pedirlo en el issue no aprueba algo de consultar"
grep -q 'code-review.*origin/<RAMA_BASE>\.\.\.HEAD' "$RAIZ/.claude/skills/implement-issue/SKILL.md"; afirmar $? "implement-issue corre /code-review sobre el diff de la rama"
(cd "$RAIZ" && git check-ignore -q .claude/worktrees/agente-x); afirmar $? ".claude/worktrees/ está ignorado (el aislamiento de Claude Code no ensucia el checkout)"
grep -qx '.claude/skills/orquestar' "$RAIZ/perfiles/chico/BORRAR" 2>/dev/null || ! [ -d "$RAIZ/perfiles" ]; afirmar $? "el modo chico borra la skill orquestar"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
