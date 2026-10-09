#!/usr/bin/env bash
# Limpia lo que deja una corrida de orquestar, para los issues ya cerrados:
# - los worktrees ../<repo>-wt/<n> (los de preparar.sh --worktree): se saca el worktree;
# - las ramas claude/<n>-… que no se mergearon (PR cerrado sin mergear): se borran la local y la
#   remota con git push origin --delete (gh pr close --delete-branch falla desde un detached HEAD).
# Sin --borrar solo lista. Nunca borra un worktree con cambios sin commitear, ni nada si quedan
# retros sin guardar en <.git común>/retros-pendientes/: la corrida no se da por cerrada hasta
# guardarlas con retro.sh.
# Uso: [BASE=<rama>] limpiar.sh [--borrar]
set -euo pipefail
BORRAR=""
case "${1:-}" in
  "") ;;
  --borrar) BORRAR=1 ;;
  *) echo "Uso: $0 [--borrar]" >&2; exit 64 ;;
esac
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PENDIENTES="$(git rev-parse --path-format=absolute --git-common-dir)/retros-pendientes"
BASE="${BASE:-<RAMA_BASE>}"   # el init de la plantilla reemplaza <RAMA_BASE>
if [[ "$BASE" == "<"*">" ]]; then
  BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true); BASE="${BASE#origin/}"
fi
errores=0

# ¿El issue está cerrado? Si no se puede leer, lo dice y lo cuenta como error (y no se toca).
cerrado() {
  local estado
  if ! estado=$(gh api "repos/$REPO/issues/$1" 2>/dev/null | jq -er .state 2>/dev/null); then
    echo "No pude leer el estado del issue #$1 ($2): ¿gh está autenticado? No lo toco." >&2
    errores=1; return 1
  fi
  [ "$estado" = closed ]
}

cerrados=(); sucios=()
while read -r ruta; do
  cerrado "${ruta##*/}" "$ruta" || continue
  if [ -n "$(git -C "$ruta" status --porcelain 2>/dev/null)" ]; then sucios+=("$ruta")
  else cerrados+=("$ruta"); fi
done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -E -- '-wt/[0-9]+$' || true)

# Ramas de issues cerrados que no están en la base: su PR se cerró sin mergear.
ramas=()
if [ -n "$BASE" ] && git rev-parse -q --verify "origin/$BASE" >/dev/null; then
  while read -r rama; do
    [[ "$rama" =~ ^claude/([0-9]+)- ]] || continue
    git merge-base --is-ancestor "$rama" "origin/$BASE" && continue
    cerrado "${BASH_REMATCH[1]}" "$rama" && ramas+=("$rama")
  done < <(git for-each-ref --format='%(refname:short)' 'refs/heads/claude/')
else
  echo "Aviso: no encuentro la rama base (origin/${BASE:-?}); no reviso ramas. Definí BASE=<rama>." >&2
fi

if [ $((${#cerrados[@]} + ${#sucios[@]} + ${#ramas[@]})) -eq 0 ]; then
  [ "$errores" = 0 ] && echo "No hay nada de issues cerrados para limpiar."
  exit "$errores"
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do echo "- worktree $r (issue cerrado)"; done
for r in ${sucios[@]+"${sucios[@]}"}; do echo "- worktree $r (issue cerrado, con cambios sin commitear: no se borra)"; done
for r in ${ramas[@]+"${ramas[@]}"}; do echo "- rama $r (issue cerrado, sin mergear en origin/$BASE)"; done
[ -n "$BORRAR" ] || { echo; echo "Para borrar: $0 --borrar"; exit "$errores"; }

if ls "$PENDIENTES"/*.md >/dev/null 2>&1; then
  echo "No borro nada: hay retros sin guardar en $PENDIENTES. Reintentá cada una con" >&2
  echo ".claude/skills/mejorar-skills/retro.sh <archivo> y volvé a correr esto." >&2
  exit 1
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do
  if git worktree remove "$r" 2>/dev/null; then echo "Borrado: $r"
  else echo "limpiar.sh: no se pudo borrar $r (¿bloqueado con git worktree lock?)." >&2; errores=1; fi
done
for r in ${ramas[@]+"${ramas[@]}"}; do
  if git ls-remote --exit-code --heads origin "$r" >/dev/null 2>&1 && ! git push -q origin --delete "$r" 2>/dev/null; then
    echo "limpiar.sh: no se pudo borrar la rama remota $r." >&2; errores=1; continue
  fi
  if git branch -q -D "$r" 2>/dev/null; then echo "Borrada: rama $r (local y remota)"
  else echo "limpiar.sh: no se pudo borrar la rama local $r (¿sigue en un worktree?)." >&2; errores=1; fi
done
exit "$errores"
