#!/usr/bin/env bash
# Tests de la rama base sin configurar (<RAMA_BASE> en la plantilla sin inicializar):
# mapa.py, verificar.py y preparar.sh usan la rama por defecto del remoto y avisan.
# Uso: bash scripts/agentes/test-base.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-base-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
unset BASE

# Remoto cuya rama por defecto es "trunk" (para no confundirla con un "main" fijo).
git init -q --bare "$TMP/remoto.git"; git -C "$TMP/remoto.git" symbolic-ref HEAD refs/heads/trunk
git clone -q "$TMP/remoto.git" "$TMP/p" 2>/dev/null
mkdir -p "$TMP/p/scripts" "$TMP/p/docs"
cp -R "$RAIZ/scripts/agentes" "$TMP/p/scripts/"
printf '{"docs": [], "sensibles": [], "verificar": [{"nombre": "eco", "siempre": true, "correr": "echo {base}"}]}\n' >"$TMP/p/docs/mapa-agentes.json"
(cd "$TMP/p" && git switch -q -c trunk && git add -A && git commit -qm base && git push -q origin trunk 2>/dev/null \
  && git remote set-head origin trunk && git switch -q -c claude/1-algo && echo x >nuevo.txt && git add nuevo.txt && git commit -qm x)

s=$(cd "$TMP/p" && python3 scripts/agentes/mapa.py 2>&1); c=$?
afirmar $c "mapa.py sin BASE en la plantilla sin inicializar termina bien"
grep -q "nuevo.txt\|Archivos cambiados: 1" <<<"$s"; afirmar $? "mapa.py compara contra la rama por defecto del remoto"
grep -qi "aviso.*trunk" <<<"$s"; afirmar $? "mapa.py avisa qué base usó"

s=$(cd "$TMP/p" && python3 scripts/agentes/verificar.py --listar 2>&1); c=$?
afirmar $c "verificar.py sin BASE termina bien"
grep -q "contra origin/trunk" <<<"$s"; afirmar $? "verificar.py usa origin/<rama por defecto>"

# Sin origin/HEAD local: la pide al remoto.
(cd "$TMP/p" && git remote set-head origin -d)
s=$(cd "$TMP/p" && python3 scripts/agentes/mapa.py 2>&1); c=$?
afirmar $c "sin origin/HEAD local, la pide al remoto"

# Con BASE explícita, no cambia nada.
s=$(cd "$TMP/p" && BASE=trunk python3 scripts/agentes/mapa.py 2>&1)
! grep -qi "aviso" <<<"$s"; afirmar $? "con BASE explícita no avisa"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
