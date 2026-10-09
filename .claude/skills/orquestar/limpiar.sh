#!/usr/bin/env bash
# Lista los worktrees de issues cerrados (../<repo>-wt/<n>, los de preparar.sh --worktree)
# y, con --borrar, los saca. Nunca borra uno con cambios sin commitear, ni ninguno si quedan
# retros sin guardar en <.git común>/retros-pendientes/ (se perderían con el worktree).
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

cerrados=(); sucios=()
while read -r ruta; do
  n="${ruta##*/}"
  estado=$(gh api "repos/$REPO/issues/$n" 2>/dev/null | jq -r .state 2>/dev/null || echo desconocido)
  [ "$estado" = closed ] || continue
  if [ -n "$(git -C "$ruta" status --porcelain 2>/dev/null)" ]; then sucios+=("$ruta")
  else cerrados+=("$ruta"); fi
done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -E -- '-wt/[0-9]+$' || true)

if [ ${#cerrados[@]} -eq 0 ] && [ ${#sucios[@]} -eq 0 ]; then echo "No hay worktrees de issues cerrados."; exit 0; fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do echo "- $r (issue cerrado)"; done
for r in ${sucios[@]+"${sucios[@]}"}; do echo "- $r (issue cerrado, con cambios sin commitear: no se borra)"; done
[ -n "$BORRAR" ] || { echo; echo "Para borrar los limpios: $0 --borrar"; exit 0; }

if ls "$PENDIENTES"/*.md >/dev/null 2>&1; then
  echo "No borro nada: hay retros sin guardar en $PENDIENTES. Reintentá cada una con" >&2
  echo ".claude/skills/mejorar-skills/retro.sh <archivo> y volvé a correr esto." >&2
  exit 1
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do git worktree remove "$r" && echo "Borrado: $r"; done
