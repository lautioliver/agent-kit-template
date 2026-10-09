#!/usr/bin/env bash
# Limpia lo que deja una corrida de orquestar, para los issues ya cerrados:
# - los worktrees ../<repo>-wt/<n> (los de preparar.sh --worktree): se saca el worktree;
# - las ramas claude/<n>-… (locales o solo remotas) cuyo PR se cerró sin mergear: se borran la
#   remota (git push origin --delete; gh pr close --delete-branch falla desde un detached HEAD) y
#   la local. Se decide por el estado del PR en GitHub, no por ancestría: así una rama mergeada
#   con squash o rebase, o un origin desactualizado, no hacen borrar trabajo mergeado.
# Una rama sin PR, con commits sin pushear o todavía en un worktree se lista para revisar a mano.
# Sin --borrar solo lista. Nunca borra un worktree con cambios sin commitear, ni nada si quedan
# retros sin guardar en <.git común>/retros-pendientes/: la corrida no se da por cerrada hasta
# guardarlas con retro.sh.
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
errores=0

# ¿El issue está cerrado? Si no se puede leer, lo dice y lo cuenta como error (y no se toca).
# El estado de cada issue se pide una sola vez (bash 3.2: sin arrays asociativos).
ESTADOS=$'\n'
cerrado() {
  local estado
  estado=$(sed -n "s/^$1=//p" <<<"$ESTADOS")
  if [ -z "$estado" ]; then
    if ! estado=$(gh api "repos/$REPO/issues/$1" 2>/dev/null | jq -er .state 2>/dev/null); then
      echo "No pude leer el estado del issue #$1 ($2): ¿gh está autenticado? No lo toco." >&2
      estado=error; errores=1
    fi
    ESTADOS+="$1=$estado"$'\n'
  fi
  [ "$estado" = closed ]
}

cerrados=(); sucios=()
while read -r ruta; do
  cerrado "${ruta##*/}" "$ruta" || continue
  if [ -n "$(git -C "$ruta" status --porcelain 2>/dev/null)" ]; then sucios+=("$ruta")
  else cerrados+=("$ruta"); fi
done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -E -- '-wt/[0-9]+$' || true)

# Ramas de issues cerrados, locales o solo remotas, decididas por el estado de su PR.
git fetch -q --prune origin 2>/dev/null || echo "Aviso: no pude actualizar origin; reviso las ramas que conozco." >&2
en_worktree=$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
ramas=(); revisar=()
while read -r rama; do
  [[ "$rama" =~ ^claude/([0-9]+)- ]] || continue
  cerrado "${BASH_REMATCH[1]}" "$rama" || continue
  if ! estados=$(gh pr list --head "$rama" --state all --json number,state 2>/dev/null | jq -r '[.[].state] | join(",")' 2>/dev/null); then
    echo "No pude leer los PRs de $rama. No la toco." >&2; errores=1; continue
  fi
  case ",$estados," in
    *,MERGED,*|*,OPEN,*) continue ;;   # mergeada (también squash o rebase) o todavía abierta
    ,,) revisar+=("$rama (issue cerrado sin PR: revisala a mano)"); continue ;;
  esac
  if grep -qxF "$rama" <<<"$en_worktree"; then revisar+=("$rama (PR cerrado sin mergear, pero sigue en un worktree)"); continue; fi
  if git rev-parse -q --verify "refs/heads/$rama" >/dev/null && git rev-parse -q --verify "refs/remotes/origin/$rama" >/dev/null \
    && [ -n "$(git rev-list "origin/$rama..$rama" 2>/dev/null)" ]; then
    revisar+=("$rama (PR cerrado sin mergear, con commits sin pushear)"); continue
  fi
  ramas+=("$rama")
done < <({ git for-each-ref --format='%(refname:short)' refs/heads/claude/
           git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/claude/; } | sort -u)

if [ $((${#cerrados[@]} + ${#sucios[@]} + ${#ramas[@]} + ${#revisar[@]})) -eq 0 ]; then
  [ "$errores" = 0 ] && echo "No hay nada de issues cerrados para limpiar."
  exit "$errores"
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do echo "- worktree $r (issue cerrado)"; done
for r in ${sucios[@]+"${sucios[@]}"}; do echo "- worktree $r (issue cerrado, con cambios sin commitear: no se borra)"; done
for r in ${ramas[@]+"${ramas[@]}"}; do echo "- rama $r (PR cerrado sin mergear)"; done
for r in ${revisar[@]+"${revisar[@]}"}; do echo "- rama $r: no se borra"; done
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
  # Primero la remota: si falla, la local queda (no se pierde la única copia).
  rc=0; git ls-remote --exit-code --heads origin "$r" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then
    git push -q origin --delete "$r" 2>/dev/null || { echo "limpiar.sh: no se pudo borrar la rama remota $r." >&2; errores=1; continue; }
  elif [ "$rc" != 2 ]; then
    echo "limpiar.sh: no pude consultar origin por $r (¿red o credenciales?). No la toco." >&2; errores=1; continue
  fi
  if git rev-parse -q --verify "refs/heads/$r" >/dev/null && ! git branch -q -D "$r" 2>/dev/null; then
    echo "limpiar.sh: borré la rama remota $r, pero no la local." >&2; errores=1; continue
  fi
  echo "Borrada: rama $r"
done
exit "$errores"
