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
git -C "$P" worktree remove "$WT/14"

# Un worktree que no se puede borrar (bloqueado) se reporta y el script sale con error.
git -C "$P" worktree lock "$WT/13"
s=$(cd "$P" && "$AQUI/limpiar.sh" --borrar 2>&1); c=$?
! es "$c" -eq 0 && grep -q "no se pudo borrar.*$WT/13" <<<"$s" && ! es -d "$WT/10"; afirmar $? "un worktree que no se puede borrar se reporta, y los demás se borran"
git -C "$P" worktree unlock "$WT/13"

s=$(cd "$P" && "$AQUI/limpiar.sh" --borrar 2>&1); c=$?
afirmar $c "limpiar.sh --borrar termina bien"
! es -d "$WT/10" && ! es -d "$WT/13"; afirmar $? "--borrar borra los worktrees limpios de issues cerrados"
es -d "$WT/11" && es -f "$WT/12/sucio.txt"; afirmar $? "--borrar no toca el abierto ni el que tiene cambios"
git -C "$P" rev-parse -q --verify claude/10-x >/dev/null; afirmar $? "--borrar deja la rama (solo saca el worktree)"

# 3. Lo que hace falta para correr en paralelo (criterios de #37).
! grep -q 'push -u' "$RAIZ/.claude/skills/implement-issue/SKILL.md"; afirmar $? "implement-issue pushea sin -u (el -u escribe .git/config y choca en paralelo)"
! grep -Eq 'pushe[aá] de nuevo[^`]*$' "$RAIZ/.claude/skills/implement-issue/SKILL.md" && grep -q 'git push origin HEAD' "$RAIZ/.claude/agents/implementador.md"; afirmar $? "cada push dice git push origin HEAD (la rama no tiene upstream)"
grep -q 'revisor.*checkout principal.*retro' "$RAIZ/docs/agentes/contrato-subagentes.md"; afirmar $? "el contrato dice que el revisor guarda la retro desde el checkout principal"
M="$RAIZ/docs/mapa-agentes.json"
for f in .claude/skills/implement-issue/SKILL.md .gitignore perfiles/chico/BORRAR; do
  python3 -c "import json,sys; v=[x for x in json.load(open('$M'))['verificar'] if x['nombre']=='orquestar'][0]; sys.exit(0 if any(g.lstrip('?')=='$f' for g in v['cuando']) else 1)"
  afirmar $? "la verificación orquestar del mapa corre cuando cambia $f"
done
R="$RAIZ/.claude/agents/revisor.md"
grep -q 'refs/revision/<pr>-<sufijo>' "$R" && grep -q -- '-revision-<pr>-<sufijo>' "$R"; afirmar $? "revisor: ref y worktree con sufijo único (dos revisiones del mismo PR no chocan)"
# shellcheck disable=SC2016  # $raiz literal del markdown
grep -q 'cd "$raiz" && .*retro.sh' "$R"; afirmar $? "revisor: guarda la retro desde el checkout principal (agente_sha de la versión que corrió)"
(cd "$RAIZ" && git check-ignore -q .claude/worktrees/agente-x); afirmar $? ".claude/worktrees/ está ignorado (el aislamiento de Claude Code no ensucia el checkout)"
grep -qx '.claude/skills/orquestar' "$RAIZ/perfiles/chico/BORRAR" 2>/dev/null || ! [ -d "$RAIZ/perfiles" ]; afirmar $? "el modo chico borra la skill orquestar"

# 4. El máximo de subagentes implementando a la vez (decisión 3 de #33) es 4, en todos los lugares.
O="$RAIZ/.claude/skills/orquestar/SKILL.md"
grep -q 'Nunca más de 4 implementando' "$O" && grep -q 'máximo de 4' "$O" && grep -q 'hasta \*\*4\*\*' "$O"; afirmar $? "orquestar: el máximo de implementadores a la vez es 4"
! grep -Eq 'más de 3|máximo de 3|hasta \*\*3\*\*' "$O" && grep -q 'Reparte hasta 4 issues' "$RAIZ/README.md"; afirmar $? "ningún lugar sigue diciendo 3 para ese máximo"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
