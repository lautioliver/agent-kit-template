#!/usr/bin/env bash
# TDD: corre los tests recién escritos ANTES de implementar y exige que fallen,
# y por la razón correcta (una aserción del comportamiento, no un import roto).
# Deja un bloque listo para pegar en "Cómo probarlo" del PR.
# Uso: rojo.sh -- <comando de test>
#   ej.: rojo.sh -- npx vitest run src/modulo
# Sale con 0 si está en rojo por una aserción; 1 si los tests pasan; 2 si fallan
# por otra razón (carga, sintaxis, símbolo inexistente).
set -uo pipefail
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "Uso: $0 -- <comando de test>" >&2; exit 64; }

salida=$(mktemp "${TMPDIR:-/tmp}/rojo-XXXXXX")
"$@" >"$salida" 2>&1
codigo=$?

if [ "$codigo" -eq 0 ]; then
  echo "Los tests PASAN sin el código nuevo: no prueban nada."
  echo "Revisá que ejerciten el criterio de aceptación (salida completa: $salida)."
  exit 1
fi

# Fallas que no son del comportamiento: el test ni llegó a correr la aserción.
mala='Cannot find module|Failed to resolve import|ERR_MODULE_NOT_FOUND|SyntaxError|ReferenceError|is not defined|is not a function|is not a constructor|Transform failed|error TS[0-9]{4}'
if grep -Eq "$mala" "$salida"; then
  echo "Los tests fallan, pero por una razón que no es el comportamiento:"
  grep -E "$mala" "$salida" | sort -u | head -5 | sed 's/^/  /'
  echo "Agregá lo mínimo para que carguen (la firma de la función, el campo en el schema)"
  echo "y volvé a correr: tienen que fallar en una aserción del criterio. Salida: $salida"
  exit 2
fi

resumen=$(grep -E '✗|×|FAIL|AssertionError|Expected|Received|expected .* to' "$salida" | sed 's/\x1b\[[0-9;]*m//g' | head -40)
fallas="${resumen:-$(tail -20 "$salida")}"
pr="${salida}.md"
{
  echo "<details><summary>Rojo antes de implementar</summary>"
  echo
  echo '```'
  echo "\$ $*"
  echo "$fallas"
  echo '```'
  echo
  echo "</details>"
} >"$pr"
echo "En rojo. Fallas:"
while IFS= read -r linea; do printf '  %s\n' "$linea"; done <<<"$fallas"
echo
echo "Confirmá que cada falla es una aserción de un criterio de aceptación."
echo "Bloque para \"Cómo probarlo\" del PR: $pr"
