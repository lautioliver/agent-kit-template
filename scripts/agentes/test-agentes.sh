#!/usr/bin/env bash
# Tests de los subagentes (.claude/agents/) y de su validación en check-docs.py.
# Corre sobre una copia del repo (git archive), así no toca el working tree.
# Uso: bash scripts/agentes/test-agentes.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-agentes-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
CONTRATO=docs/agentes/contrato-subagentes.md
AGENTES=".claude/agents"

# Copia del repo con lo commiteado y lo que está en el working tree.
copia() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"
  (cd "$RAIZ" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | tar -xf - -C "$TMP/r"
  (cd "$TMP/r" && git init -q && git add -A && git commit -qm base)
}
check() { (cd "$TMP/r" && python3 scripts/agentes/check-docs.py 2>&1); }
frontmatter() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$1"; }

# 1. Los tres roles existen con su modelo y herramientas acotadas.
for par in implementador:sonnet implementador-liviano:haiku revisor:opus; do
  rol=${par%%:*}; modelo=${par##*:}; f="$RAIZ/$AGENTES/$rol.md"
  fm=$(frontmatter "$f" 2>/dev/null)
  grep -qx "name: $rol" <<<"$fm"; afirmar $? "$rol: existe con name: $rol"
  grep -qx "model: $modelo" <<<"$fm"; afirmar $? "$rol: model: $modelo"
  grep -q "^tools: " <<<"$fm"; afirmar $? "$rol: lista sus herramientas (tools:)"
  grep -q "$CONTRATO" "$f" 2>/dev/null; afirmar $? "$rol: remite al contrato de salida común"
done
! grep -q "Edit" <<<"$(frontmatter "$RAIZ/$AGENTES/revisor.md" 2>/dev/null | grep '^tools:')"; afirmar $? "revisor: no puede editar código (Write solo para la revisión y la retro)"

# 2. El contrato de salida está en un solo lugar, con todos los resultados.
for r in pr consulta escalar soltado bloqueantes; do
  grep -q "\`$r\`" "$RAIZ/$CONTRATO" 2>/dev/null; afirmar $? "el contrato define el resultado $r"
done
grep -q "retro.sh" "$RAIZ/$CONTRATO" 2>/dev/null; afirmar $? "el contrato dice que cada subagente guarda su retro con retro.sh"

# 3. El liviano dice exactamente cuándo escalar.
f="$RAIZ/$AGENTES/implementador-liviano.md"
grep -q "mapa.py" "$f" 2>/dev/null && grep -q "rutas sensibles" "$f" && grep -q "logica-negocio" "$f"
afirmar $? "implementador-liviano: escala por rutas sensibles (mapa.py) o lógica de negocio"

# 4. check-docs.py valida los subagentes.
copia
check >/dev/null; afirmar $? "check-docs pasa con los subagentes del repo"
mkdir -p "$TMP/r/$AGENTES"
printf -- '---\nname: x\ndescription: d\ntools: Read\nmodel: gpt-4\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*model" <<<"$salida"; afirmar $? "check-docs rechaza un model que no es opus, sonnet ni haiku"
printf -- '---\nname: x\ndescription: d\nmodel: haiku\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*tools" <<<"$salida"; afirmar $? "check-docs rechaza un subagente sin tools"
printf -- '---\nname: x\ndescription: d\ntools: Read\nmodel: haiku\n---\nSin contrato.\n' >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*contrato" <<<"$salida"; afirmar $? "check-docs rechaza un subagente que no remite al contrato"
printf -- '---\r\nname: x\r\ndescription: d\r\ntools: Read\r\nmodel: haiku\r\n---\r\nVer %s.\r\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
check >/dev/null; afirmar $? "check-docs acepta un subagente con fin de línea CRLF"
printf -- '---\nname: "x"\ndescription: d\ntools: Read\nmodel: "haiku"\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
check >/dev/null; afirmar $? "check-docs acepta valores entre comillas"

# 5. El modo chico no deja los subagentes.
grep -qx "$AGENTES" "$RAIZ/perfiles/chico/BORRAR"; afirmar $? "el modo chico borra $AGENTES"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
