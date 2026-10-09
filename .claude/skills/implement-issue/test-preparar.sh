#!/usr/bin/env bash
# Tests de preparar.sh contra un remoto local y un gh falso (no usa GitHub).
# Uso: bash .claude/skills/implement-issue/test-preparar.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
PREPARAR="$AQUI/preparar.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-preparar-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
es() { test "$@"; }

# gh falso: issues abiertos, sin bloqueos, sin épica ni comentarios. Registra cada llamada.
mkdir -p "$TMP/bin" "$TMP/issues"
export GH_LOG="$TMP/gh.log" GH_ISSUES="$TMP/issues"
cat >"$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
  "repo view"*) echo o/r ;;
  "api user"*) echo yo ;;
  api\ repos/o/r/issues/*/dependencies/*) echo '[]' ;;
  api\ repos/o/r/issues/*/parent*) exit 1 ;;
  api\ repos/o/r/issues/*/comments*) ;;
  api\ repos/o/r/issues/*) cat "$GH_ISSUES/${2##*/}.json" ;;
  "issue edit"*) ;;
  *) echo "gh falso: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
# Aislado de la config de git de quien corre los tests (firma de commits, hooks globales…).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export PATH="$TMP/bin:$PATH" BASE=main GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
issue() { # issue <n> <título>
  printf '{"state":"open","title":"%s","labels":[],"assignees":[],"html_url":"u","body":"cuerpo"}\n' "$2" >"$TMP/issues/$1.json"
}
issue 36 "Hacer algo"; issue 37 "Otra cosa"; issue 38 "Solo mirar"; issue 40 "Sin worktree"; issue 41 "Con lock"

git init -q --bare "$TMP/remoto.git"
git clone -q "$TMP/remoto.git" "$TMP/proj" 2>/dev/null
(cd "$TMP/proj" && git switch -q -c main && echo base >README.md && git add README.md && git commit -qm base && git push -q origin main 2>/dev/null)
WT="$TMP/proj-wt"
asignado() { grep -q "^issue edit $1 .*--add-assignee @me" "$GH_LOG"; }
worktrees() { git -C "$TMP/proj" worktree list | wc -l | tr -d ' '; }

# 1. Issue nuevo: crea el worktree y la rama, y lo asigna. El checkout principal sucio no lo frena.
echo sucio >"$TMP/proj/sucio.txt"
s=$(cd "$TMP/proj" && "$PREPARAR" 36 --worktree 2>&1); c=$?
afirmar $c "--worktree con un issue nuevo termina bien aunque el checkout principal esté sucio"
es -d "$WT/36"; afirmar $? "crea el worktree en ../<repo>-wt/<n>"
es "$(git -C "$WT/36" branch --show-current 2>/dev/null)" = "claude/36-hacer-algo"; afirmar $? "el worktree está en la rama claude/<n>-<descripcion>"
grep -qx "Worktree: $WT/36" <<<"$s"; afirmar $? "imprime la línea 'Worktree: <ruta>'"
grep -q "^Rama nueva: claude/36-hacer-algo (desde origin/main)" <<<"$s"; afirmar $? "dice que la rama es nueva y desde dónde sale"
asignado 36; afirmar $? "asigna el issue"
es "$(git -C "$TMP/proj" branch --show-current)" = main; afirmar $? "el checkout principal sigue en su rama"
rm -f "$TMP/proj/sucio.txt"

# 2. Worktree existente: lo retoma sin crear otro.
antes=$(worktrees)
s=$(cd "$TMP/proj" && "$PREPARAR" 36 --worktree 2>&1); c=$?
afirmar $c "--worktree con un worktree existente termina bien"
es "$(worktrees)" = "$antes"; afirmar $? "no crea otro worktree"
grep -q "^Rama existente: claude/36-hacer-algo (retomando)" <<<"$s"; afirmar $? "dice que retoma la rama"
grep -qx "Worktree: $WT/36" <<<"$s"; afirmar $? "imprime la misma ruta al retomar"

# 2b. El árbol limpio se valida sobre el worktree.
{ echo x >"$WT/36/pendiente.txt"; } 2>/dev/null
(cd "$TMP/proj" && "$PREPARAR" 36 --worktree >/dev/null 2>&1); c=$?
es "$c" -ne 0; afirmar $? "falla si el worktree tiene cambios sin commitear"
rm -f "$WT/36/pendiente.txt"

# 3. Rama en uso en otro worktree: falla con mensaje claro y no asigna.
git -C "$TMP/proj" worktree add -q -b claude/37-otra-cosa "$TMP/otro" origin/main 2>/dev/null
s=$(cd "$TMP/proj" && "$PREPARAR" 37 --worktree 2>&1); c=$?
es "$c" -ne 0; afirmar $? "falla si la rama está en otro worktree"
grep -q "otro worktree.*$TMP/otro" <<<"$s"; afirmar $? "el mensaje dice en qué worktree está la rama"
! asignado 37; afirmar $? "no asigna si la rama está en otro worktree"
! [ -e "$WT/37" ]; afirmar $? "no crea el worktree si la rama está en otro"

# 4. --revisar no crea nada, en cualquier orden con --worktree.
for args in "--revisar --worktree" "--worktree --revisar"; do
  # shellcheck disable=SC2086  # se separan a propósito
  s=$(cd "$TMP/proj" && "$PREPARAR" 38 $args 2>&1); c=$?
  afirmar $c "$args termina bien"
  ! [ -e "$WT/38" ] && ! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/38-solo-mirar; afirmar $? "$args no crea worktree ni rama"
  grep -q "$WT/38" <<<"$s"; afirmar $? "$args muestra el worktree propuesto"
done
! asignado 38; afirmar $? "--revisar no asigna"

# 5. Sin --worktree, como hoy: cambia la rama del checkout principal y no crea worktrees.
antes=$(worktrees)
s=$(cd "$TMP/proj" && "$PREPARAR" 40 2>&1); c=$?
afirmar $c "sin --worktree termina bien"
es "$(git -C "$TMP/proj" branch --show-current)" = claude/40-sin-worktree; afirmar $? "sin --worktree cambia la rama del checkout principal"
[ "$(worktrees)" = "$antes" ] && ! grep -q '^Worktree:' <<<"$s"; afirmar $? "sin --worktree no crea ni menciona worktrees"
tail -2 <<<"$s" | head -1 | grep -qx "Rama nueva: claude/40-sin-worktree (desde origin/main)"; afirmar $? "sin --worktree la salida termina como hoy"
git -C "$TMP/proj" switch -q main
echo sucio >"$TMP/proj/sucio.txt"
(cd "$TMP/proj" && "$PREPARAR" 41 >/dev/null 2>&1); c=$?
[ "$c" -ne 0 ] && ! asignado 41; afirmar $? "sin --worktree, el checkout principal sucio sigue frenando"
rm -f "$TMP/proj/sucio.txt"

# 6. git fetch se reintenta si falla por un lock de .git.
cat >"$TMP/bin/git" <<SH
#!/usr/bin/env bash
if [ "\$1" = fetch ] && [ ! -e "$TMP/lock-ya" ]; then
  touch "$TMP/lock-ya"
  echo "fatal: Unable to create '$TMP/proj/.git/shallow.lock': File exists." >&2; exit 128
fi
exec $(command -v git) "\$@"
SH
chmod +x "$TMP/bin/git"
(cd "$TMP/proj" && "$PREPARAR" 41 --worktree >/dev/null 2>&1); c=$?
afirmar $c "reintenta git fetch si falla por un lock"
rm -f "$TMP/bin/git"

# 7. Hallazgos de /code-review.
issue 42 "Huerfano"; issue 43 "Desde worktree"; issue 44 "Sin fetch"
(cd "$TMP/proj" && "$PREPARAR" 42 --worktree >/dev/null 2>&1)
rm -rf "$WT/42"
s=$(cd "$TMP/proj" && "$PREPARAR" 42 --worktree 2>&1); c=$?
afirmar $c "retoma aunque la carpeta del worktree se haya borrado a mano"
es -d "$WT/42"; afirmar $? "vuelve a crear la carpeta del worktree borrado"

s=$(cd "$TMP/proj" && "$PREPARAR" 36 2>&1); c=$?
es "$c" -ne 0; afirmar $? "sin --worktree falla si la rama está en un worktree"
grep -q "otro worktree" <<<"$s"; afirmar $? "sin --worktree dice en qué worktree está la rama"
es "$(grep -c "^issue edit 36 " "$GH_LOG")" -eq 2; afirmar $? "sin --worktree no asigna si la rama está en un worktree"

s=$(cd "$WT/36" && "$PREPARAR" 43 --worktree 2>&1); c=$?
afirmar $c "--worktree funciona corriendo desde otro worktree"
grep -qx "Worktree: $WT/43" <<<"$s"; afirmar $? "desde otro worktree, el nuevo va al lado del checkout principal"

(cd "$TMP/proj" && "$PREPARAR" ../44 --worktree >/dev/null 2>&1); c=$?
es "$c" -eq 64 && ! grep -q 'issues/\.\.' "$GH_LOG"; afirmar $? "rechaza un número de issue inválido sin llamar a gh"

git -C "$TMP/proj" remote set-url origin "$TMP/no-existe.git"
(cd "$TMP/proj" && "$PREPARAR" 44 --worktree >/dev/null 2>&1); c=$?
es "$c" -ne 0 && ! asignado 44; afirmar $? "con --worktree no asigna si no pudo crear el worktree"
git -C "$TMP/proj" remote set-url origin "$TMP/remoto.git"

# 8. Hallazgos de la revisión del PR #40.
issue 45 "Con config bloqueada"; issue 46 "Worktree bloqueado"
touch "$TMP/proj/.git/config.lock"
(cd "$TMP/proj" && "$PREPARAR" 45 --worktree >/dev/null 2>&1); c=$?
rm -f "$TMP/proj/.git/config.lock"
afirmar $c "--worktree no necesita escribir .git/config (otro agente puede tenerlo bloqueado)"

git -C "$TMP/proj" worktree add -q -b claude/46-worktree-bloqueado "$TMP/bloqueado" origin/main 2>/dev/null
git -C "$TMP/proj" worktree lock "$TMP/bloqueado"; rm -rf "$TMP/bloqueado"
for args in "--worktree" ""; do
  # shellcheck disable=SC2086  # vacío a propósito
  s=$(cd "$TMP/proj" && "$PREPARAR" 46 $args 2>&1); c=$?
  es "$c" -eq 1 && grep -q "NO SE PUEDE TOMAR #46: .*bloqueado" <<<"$s"; afirmar $? "${args:-sin --worktree}: un worktree bloqueado y sin carpeta da un error claro"
done
! asignado 46; afirmar $? "no asigna si la rama está en un worktree bloqueado sin carpeta"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
