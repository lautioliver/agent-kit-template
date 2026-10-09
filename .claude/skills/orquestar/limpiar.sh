#!/usr/bin/env bash
# Limpia lo que deja una corrida de orquestar, para los issues ya cerrados:
# - los worktrees ../<repo>-wt/<n> (los de preparar.sh --worktree): se saca el worktree;
# - las ramas claude/<n>-… (locales o remotas) cuyo PR se cerró sin mergear: solo se listan, con
#   el comando para borrarlas (git push origin --delete; gh pr close --delete-branch falla desde un
#   detached HEAD). Borrar una rama puede perder trabajo, así que lo decide la persona. Se decide
#   por el estado del PR en GitHub, no por ancestría (sirve con squash y rebase).
# Sin --borrar solo lista; --borrar solo saca worktrees. Nunca saca uno con cambios sin commitear,
# ni ninguno si quedan retros sin guardar en <.git común>/retros-pendientes/: la corrida no se
# da por cerrada hasta guardarlas con retro.sh.
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

# Ramas de issues cerrados (locales o remotas, sin fetch: listar no cambia nada), por el estado de su PR.
ramas=(); avisos=()
while read -r rama; do
  [[ "$rama" =~ ^claude/([0-9]+)- ]] || continue
  cerrado "${BASH_REMATCH[1]}" "$rama" || continue
  if ! estados=$(gh pr list --head "$rama" --state all --json number,state 2>/dev/null | jq -r '[.[].state] | join(",")' 2>/dev/null); then
    echo "No pude leer los PRs de $rama." >&2; errores=1; continue
  fi
  case ",$estados," in
    *,MERGED,*|*,OPEN,*) continue ;;   # mergeada (también squash o rebase) o todavía abierta
    ,,) avisos+=("$rama (issue cerrado sin PR: revisala antes de borrarla)"); continue ;;
  esac
  if git rev-parse -q --verify "refs/heads/$rama" >/dev/null \
    && [ -n "$(git rev-list "$rama" --not --remotes=origin 2>/dev/null)" ]; then
    avisos+=("$rama (PR cerrado sin mergear, con commits sin pushear)"); continue
  fi
  ramas+=("$rama")
done < <({ git for-each-ref --format='%(refname:short)' refs/heads/claude/
           git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/claude/; } | sort -u)

if [ $((${#cerrados[@]} + ${#sucios[@]} + ${#ramas[@]} + ${#avisos[@]})) -eq 0 ]; then
  [ "$errores" = 0 ] && echo "No hay nada de issues cerrados para limpiar."
  exit "$errores"
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do echo "- worktree $r (issue cerrado)"; done
for r in ${sucios[@]+"${sucios[@]}"}; do echo "- worktree $r (issue cerrado, con cambios sin commitear: no se borra)"; done
for r in ${ramas[@]+"${ramas[@]}"}; do echo "- rama $r (PR cerrado sin mergear)"; done
for r in ${avisos[@]+"${avisos[@]}"}; do echo "- rama $r"; done
if [ ${#ramas[@]} -gt 0 ]; then
  echo; echo "Las ramas no se borran solas. Si la persona confirma, por cada una:"
  echo "  git push origin --delete <rama>; git branch -D <rama>"
fi
[ -n "$BORRAR" ] || { echo; echo "Para sacar los worktrees: $0 --borrar"; exit "$errores"; }

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
