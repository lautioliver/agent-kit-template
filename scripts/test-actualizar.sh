#!/usr/bin/env bash
# Tests de actualizar.py de punta a punta: dos versiones locales de la plantilla (v0.1.0 y v0.2.0),
# un proyecto iniciado con la primera y cambios de los dos lados.
# Uso: bash scripts/test-actualizar.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-actualizar-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

# La plantilla tal como está en el árbol, en un repo con dos versiones etiquetadas.
P="$TMP/plantilla"
mkdir -p "$P"
(cd "$RAIZ" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf -) | (cd "$P" && tar -xf -)
(
  cd "$P" && git init -q -b main
  echo 0.1.0 >VERSION
  for f in viejo viejo2 borrado; do echo "$f v0.1" >".claude/skills/debug/$f.md"; done
  git add -A && git commit -qm v0.1.0 && git tag v0.1.0
  echo 0.2.0 >VERSION
  printf '\n## 0.2.0\n\n- Cambio de prueba.\n' >>CHANGELOG.md
  echo "Línea nueva de la plantilla v0.2." >>.claude/skills/debug/SKILL.md
  echo "Línea nueva de la plantilla v0.2." >>AGENTS.md
  perl -pi -e 's/^# .*/# Plantilla v0.2/ if $. == 1' docs/convencion-nombres-github.md
  echo "nuevo v0.2" >.claude/skills/debug/nuevo.md
  echo "borrado v0.2" >.claude/skills/debug/borrado.md
  git rm -q .claude/skills/debug/viejo.md .claude/skills/debug/viejo2.md
  git add -A && git commit -qm v0.2.0 && git tag v0.2.0
) >/dev/null 2>&1

# Proyecto iniciado con v0.1.0: <modo> en <dir>.
proyecto() {
  local dir=$1 modo=$2
  mkdir -p "$dir"
  git -C "$P" archive v0.1.0 | tar -xf - -C "$dir"
  local extra=(); [ "$modo" = chico ] && extra=(--chico)
  (cd "$dir" && git init -q -b main && git add -A && git commit -qm plantilla \
    && ./scripts/init-plantilla.sh Demo main ${extra[@]+"${extra[@]}"} && git add -A && git commit -qm init) >/dev/null 2>&1
}

D="$TMP/completo"
proyecto "$D" completo
grep -q '"version": "0.1.0"' "$D/.agent-kit.json"; afirmar $? "el init registra la versión de la plantilla en .agent-kit.json"
! [ -e "$D/VERSION" ] && ! [ -e "$D/CHANGELOG.md" ]; afirmar $? "el init borra VERSION y CHANGELOG.md (son de la plantilla)"
[ -f "$D/scripts/actualizar.py" ]; afirmar $? "el proyecto completo trae actualizar.py"
(
  cd "$D"
  perl -pi -e 's/^# .*/# AGENTS.md — Demo (editado)/ if $. == 1' AGENTS.md
  perl -pi -e 's/^# .*/# Convención del proyecto/ if $. == 1' docs/convencion-nombres-github.md
  echo "cambio del proyecto" >>.claude/skills/debug/viejo2.md
  git rm -q .claude/skills/debug/borrado.md
  git commit -qam "cambios del proyecto"
) >/dev/null 2>&1

echo sucio >>"$D/AGENTS.md"
s=$(cd "$D" && python3 scripts/actualizar.py --plantilla "$P" 2>&1); c=$?
[ "$c" -ne 0 ] && grep -qi "sin commitear" <<<"$s"; afirmar $? "no actualiza con cambios sin commitear"
(cd "$D" && git checkout -q AGENTS.md)

antes=$(git -C "$D" rev-parse HEAD)
s=$(cd "$D" && python3 scripts/actualizar.py --plantilla "$P" 2>&1); c=$?
afirmar "$c" "actualiza de v0.1.0 a la última versión (v0.2.0)"
grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md"; afirmar $? "reemplaza un archivo que el proyecto no tocó"
grep -q "Demo (editado)" "$D/AGENTS.md" && grep -q "Línea nueva de la plantilla v0.2." "$D/AGENTS.md"
afirmar $? "fusiona un archivo que tocaron los dos lados en lugares distintos"
head -1 "$D/docs/convencion-nombres-github.md" | grep -q "Convención del proyecto" \
  && grep -q '^<<<<<<<' "$D/.agent-kit/pendientes/docs/convencion-nombres-github.md"
afirmar $? "con conflicto no pisa el archivo: deja la fusión con marcas en .agent-kit/pendientes/"
[ -f "$D/.claude/skills/debug/nuevo.md" ]; afirmar $? "agrega un archivo nuevo de la plantilla"
! [ -e "$D/.claude/skills/debug/viejo.md" ]; afirmar $? "borra un archivo que la plantilla sacó y el proyecto no tocó"
[ -f "$D/.claude/skills/debug/viejo2.md" ] && grep -q "viejo2.md" <<<"$s"
afirmar $? "conserva y avisa un archivo que la plantilla sacó pero el proyecto modificó"
! [ -e "$D/.claude/skills/debug/borrado.md" ]; afirmar $? "no vuelve a traer un archivo que el proyecto borró"
grep -q '"version": "0.2.0"' "$D/.agent-kit.json"; afirmar $? "registra la versión nueva en .agent-kit.json"
grep -q "Cambio de prueba" <<<"$s"; afirmar $? "muestra el changelog de las versiones nuevas"
[ "$(git -C "$D" rev-parse HEAD)" = "$antes" ] && [ -n "$(git -C "$D" status --porcelain)" ]
afirmar $? "no commitea: los cambios quedan en el working tree"
! grep -rq '<PROYECTO>\|<RAMA_BASE>' "$D/.claude/skills/debug/SKILL.md" "$D/AGENTS.md"
afirmar $? "los archivos traídos tienen los datos del proyecto, no los marcadores"

(cd "$D" && rm -rf .agent-kit && git checkout -q docs/convencion-nombres-github.md && git add -A && git commit -qm actualizar) >/dev/null 2>&1
s=$(cd "$D" && python3 scripts/actualizar.py --plantilla "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -qi "ya está" <<<"$s" && [ -z "$(git -C "$D" status --porcelain)" ]
afirmar $? "si ya está en la última versión, no cambia nada"

# Modo chico.
D="$TMP/chico"
proyecto "$D" chico
s=$(cd "$D" && python3 scripts/actualizar.py --plantilla "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" \
  && grep -q '"modo": "chico"' "$D/.agent-kit.json" && ! [ -e "$D/.claude/skills/review-pr" ]
afirmar $? "[chico] actualiza sin traer lo del modo completo"

# crecer.py (chico → completo) también registra la versión de la plantilla que trae.
D="$TMP/crece"
proyecto "$D" chico
s=$(cd "$D" && AGENT_KIT_PLANTILLA="$P" python3 scripts/crecer.py 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q '"version": "0.2.0"' "$D/.agent-kit.json" && grep -q '"modo": "completo"' "$D/.agent-kit.json"
afirmar $? "crecer.py registra la versión de la plantilla que trajo"

# Proyecto anterior a las versiones: sin "version" en .agent-kit.json.
D="$TMP/anterior"
proyecto "$D" completo
(
  cd "$D"
  python3 -c "import json; k=json.load(open('.agent-kit.json')); k.pop('version', None); json.dump(k, open('.agent-kit.json', 'w'), indent=2)"
  perl -pi -e 's/^# .*/# AGENTS.md — Demo (editado)/ if $. == 1' AGENTS.md
  git commit -qam anterior
) >/dev/null 2>&1
s=$(cd "$D" && python3 scripts/actualizar.py --plantilla "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" \
  && grep -q "Demo (editado)" "$D/AGENTS.md" && [ -f "$D/.agent-kit/pendientes/AGENTS.md" ]
afirmar $? "[sin versión] reemplaza lo no tocado y deja lo modificado en pendientes, sin fusionar"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
