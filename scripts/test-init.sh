#!/usr/bin/env bash
# Tests de init-plantilla.sh sobre una copia de la plantilla, en modo completo y chico:
# lo que AGENTS.md dice que está ignorado lo está, y los scripts de agentes no ensucian el árbol.
# Uso: bash scripts/test-init.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-init-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
unset BASE

# Copia de la plantilla tal como está en el árbol (incluye lo nuevo sin commitear, sin lo ignorado).
copiar() { # copiar <destino>
  mkdir -p "$1"
  (cd "$RAIZ" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf -) | (cd "$1" && tar -xf -)
  (cd "$1" && git init -q -b main && git add -A && git commit -qm plantilla)
}

for modo in completo chico; do
  p="$TMP/$modo"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--chico)
  (cd "$p" && ./scripts/init-plantilla.sh Demo main ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); afirmar $? "[$modo] el init termina bien"
  (cd "$p" && git add -A && git commit -qm init)

  ! [ -e "$p/scripts/test-init.sh" ]; afirmar $? "[$modo] el init borra este test (no sirve sin init-plantilla.sh)"
  n=$(cd "$p" && git check-ignore .env .env.local scripts/agentes/__pycache__ | wc -l | tr -d ' ')
  es "$n" = 3; afirmar $? "[$modo] .env, .env.local y __pycache__ están ignorados"
  ! (cd "$p" && git check-ignore -q .env.example); afirmar $? "[$modo] .env.example no está ignorado"

  echo "SECRET=x" >"$p/.env"
  if [ -f "$p/scripts/agentes/verificar.py" ]; then
    s=$(cd "$p" && python3 scripts/agentes/verificar.py --listar 2>&1)
    ! grep -q '\.env\|__pycache__' <<<"$s"; afirmar $? "[$modo] verificar.py no lista .env ni __pycache__"
  fi
  (cd "$p" && python3 scripts/agentes/check-docs.py >/dev/null 2>&1)
  es -z "$(cd "$p" && git status --porcelain)"; afirmar $? "[$modo] después de correr los scripts, git status queda limpio"
done

# check-docs.py falla si AGENTS.md dice que algo está ignorado y no lo está.
p="$TMP/completo"
s=$(cd "$p" && python3 scripts/agentes/check-docs.py 2>&1)
! grep -q 'ignorad' <<<"$s"; afirmar $? "check-docs.py no se queja si lo que AGENTS.md dice ignorado lo está"
(cd "$p" && git rm -q .gitignore)
s=$(cd "$p" && python3 scripts/agentes/check-docs.py 2>&1); c=$?
[ "$c" -ne 0 ] && grep -q 'AGENTS.md.*\.env.*ignorad' <<<"$s"; afirmar $? "check-docs.py falla si AGENTS.md dice que .env* está ignorado y no lo está"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
