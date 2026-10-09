#!/usr/bin/env bash
# Lista los worktrees de issues cerrados (../<repo>-wt/<n>, los de preparar.sh --worktree)
# y, con --borrar, los saca. Nunca borra uno con cambios sin commitear, ni ninguno si quedan
# retros sin guardar en <.git común>/retros-pendientes/: la corrida no se da por cerrada hasta
# guardarlas con retro.sh.
# La rama queda: solo se saca el worktree.
# Uso: limpiar.sh [--borrar]
set -euo pipefail
BORRAR=""
case "${1:-}" in
  "") ;;
  --borrar) BORRAR=1 ;;
  *) echo "Uso: $0 [--borrar]" >&2; exit 64 ;;
esac
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PENDIENTES="$(git rev-parse --path-format=absolute --git-common-dir)/retros-pendientes"

cerrados=(); sucios=(); errores=0
while read -r ruta; do
  n="${ruta##*/}"
  if ! estado=$(gh api "repos/$REPO/issues/$n" 2>/dev/null | jq -er .state 2>/dev/null); then
    echo "No pude leer el estado del issue #$n ($ruta): ¿gh está autenticado? No lo toco." >&2
    errores=1; continue
  fi
  [ "$estado" = closed ] || continue
  if [ -n "$(git -C "$ruta" status --porcelain 2>/dev/null)" ]; then sucios+=("$ruta")
  else cerrados+=("$ruta"); fi
done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -E -- '-wt/[0-9]+$' || true)

if [ ${#cerrados[@]} -eq 0 ] && [ ${#sucios[@]} -eq 0 ]; then
  [ "$errores" = 0 ] && echo "No hay worktrees de issues cerrados."
  exit "$errores"
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do echo "- $r (issue cerrado)"; done
for r in ${sucios[@]+"${sucios[@]}"}; do echo "- $r (issue cerrado, con cambios sin commitear: no se borra)"; done
[ -n "$BORRAR" ] || { echo; echo "Para borrar los limpios: $0 --borrar"; exit "$errores"; }

if ls "$PENDIENTES"/*.md >/dev/null 2>&1; then
  echo "No borro nada: hay retros sin guardar en $PENDIENTES. Reintentá cada una con" >&2
  echo ".claude/skills/mejorar-skills/retro.sh <archivo> y volvé a correr esto." >&2
  exit 1
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do
  if git worktree remove "$r" 2>/dev/null; then echo "Borrado: $r"
  else echo "limpiar.sh: no se pudo borrar $r (¿bloqueado con git worktree lock?)." >&2; errores=1; fi
done
exit "$errores"
