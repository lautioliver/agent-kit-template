#!/usr/bin/env python3
"""Barandas: hook PreToolUse de Claude Code que frena, antes de correrlos, los comandos que un
agente nunca corre solo (AGENTS.md, Autonomía → Nunca): mergear o aprobar PRs, pushear a una rama
troncal, crear tags o releases, tocar la protección de ramas y saltear hooks con --no-verify.

Se registra en .claude/settings.json. Lee el JSON del hook por stdin; si frena, sale con 2 y
explica en stderr qué hacer (Claude Code se lo muestra al agente). Si la persona pidió el paso,
lo corre ella en el chat con `! <comando>`. A propósito no hay variable para desactivarlo: la
podría poner el agente.

Son barandas, no una cerradura: frenan el error común (el agente que mergea porque es el paso que
sigue), no un script que haga lo mismo por otro camino. La cerradura es la protección de ramas.
"""
import json
import os
import re
import shlex
import subprocess
import sys

TRONCALES = {"main", "master", "develop", "<RAMA_BASE>"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
GIT_OPC_CON_VALOR = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
CON_NO_VERIFY = {"commit", "push", "merge", "am", "rebase", "cherry-pick", "revert", "pull"}
COMMIT_CON_VALOR = set("mFcCtuS")  # opciones cortas de commit cuyo valor puede ir pegado
TAG_LISTAR = {"-l", "--list", "-v", "--verify", "--contains", "--no-contains", "--points-at", "--merged",
              "--no-merged"}
TAG_CON_VALOR = {"-m", "--message", "-F", "--file", "-u", "--local-user", "--sort", "--format", "--cleanup",
                 "--color", "--column", "--contains", "--no-contains", "--points-at", "--merged", "--no-merged"}
PUSH_CON_VALOR = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
MUTACIONES_GRAPHQL = ("mergePullRequest", "enablePullRequestAutoMerge", "mergeBranch", "createRef", "updateRef",
                      "createRelease", "deleteBranchProtectionRule", "updateBranchProtectionRule")
TRONCAL_RE = "|".join(re.escape(t) for t in sorted(TRONCALES))


def sin_comentarios(texto):
    """Saca los comentarios (# al principio de una palabra) y vacía los $'…', fuera de comillas.

    shlex no entiende ninguno de los dos: un apóstrofo en un comentario parecería una comilla sin
    cerrar."""
    fuera, i, n = [], 0, len(texto)
    while i < n:
        c = texto[i]
        if c == "\\":
            fuera.append(texto[i:i + 2])
            i += 2
        elif texto.startswith("$'", i):
            j = i + 2
            while j < n and texto[j] != "'":
                j += 2 if texto[j] == "\\" else 1
            fuera.append("''")
            i = j + 1
        elif c == "'":
            j = texto.find("'", i + 1)
            j = n if j < 0 else j
            fuera.append(texto[i:j + 1])
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and texto[j] != '"':
                j += 2 if texto[j] == "\\" else 1
            fuera.append(texto[i:j + 1])
            i = j + 1
        elif c == "#" and (i == 0 or texto[i - 1] in " \t\n;&|()"):
            j = texto.find("\n", i)
            i = n if j < 0 else j
        else:
            fuera.append(c)
            i += 1
    return "".join(fuera)


def sacar_heredocs(texto):
    """El cuerpo de un heredoc es texto, no comandos: se saca antes de analizar."""
    fuera, fin = [], None
    for linea in texto.split("\n"):
        if fin is not None:
            if linea.strip() == fin:
                fin = None
            continue
        fuera.append(linea)
        m = re.search(r"(?<![<\w])<<-?(?!<)\s*(['\"]?)([^\s'\"<>;&|()]+)\1", linea)
        if m:
            fin = m.group(2)
    return "\n".join(fuera)


def sustituciones(texto):
    """Lo que corre dentro de $(…) y `…`, salvo entre comillas simples."""
    dentro, i, simples = [], 0, False
    while i < len(texto):
        c = texto[i]
        if c == "\\" and not simples:
            i += 2
            continue
        if c == "'":
            simples = not simples
        elif not simples and texto.startswith("$(", i):
            nivel, j = 1, i + 2
            while j < len(texto) and nivel:
                nivel += {"(": 1, ")": -1}.get(texto[j], 0)
                j += 1
            dentro.append(texto[i + 2:j - 1])
            i = j
            continue
        elif not simples and c == "`":
            j = texto.find("`", i + 1)
            j = len(texto) if j < 0 else j
            dentro.append(texto[i + 1:j])
            i = j + 1
            continue
        i += 1
    return dentro


def comandos(texto):
    """Parte el texto en comandos simples (listas de palabras)."""
    texto = texto.replace("\n", " ; ")
    try:
        lex = shlex.shlex(texto, posix=True, punctuation_chars=";&|()")
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
    except ValueError:
        # Comillas que shlex no entiende: mejor partir de más que dejar pasar el comando.
        tokens = re.findall(r"[;&|()]+|[^\s;&|()'\"]+", texto)
    actual = []
    for tok in tokens:
        if set(tok) <= set(";&|()"):
            if actual:
                yield actual
            actual = []
        else:
            actual.append(tok)
    if actual:
        yield actual


def antes_de_dobleguion(args):
    return args[:args.index("--")] if "--" in args else args


def es_no_verify(a):
    return re.match(r"^--no-veri(f|fy)?$", a) is not None


def commit_con_n(a):
    """-n (--no-verify) dentro de un grupo de opciones cortas de commit, como -an."""
    if not re.match(r"^-[a-zA-Z]", a):
        return False
    for c in a[1:]:
        if c == "n":
            return True
        if c in COMMIT_CON_VALOR:
            return False
    return False


class Contexto:
    def __init__(self, rama_actual, es_tag, cwd):
        self.rama_actual, self.es_tag, self.base = rama_actual, es_tag, cwd

    def rama(self, cwd):
        """La rama de cwd; si no existe (un cd a un directorio nuevo), la del directorio de partida."""
        for d in (cwd, self.base):
            try:
                return self.rama_actual(d)
            except Exception:
                continue
        return None

    def tag(self, nombre, cwd):
        try:
            return self.es_tag(nombre, cwd)
        except Exception:
            return False


def analizar_git(args, cwd, ctx):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] in GIT_OPC_CON_VALOR and i + 1 < len(args):
            valor = args[i + 1]
            if args[i] == "-C":
                cwd = os.path.join(cwd or os.getcwd(), valor)
            if args[i] == "-c" and valor.lower().startswith("core.hookspath"):
                return "saltear los hooks de git (core.hooksPath)"
            i += 2
        else:
            i += 1
    if i >= len(args):
        return None
    sub, resto = args[i], antes_de_dobleguion(args[i + 1:])
    if sub in CON_NO_VERIFY and any(es_no_verify(a) for a in resto):
        return "saltear los hooks y checks con --no-verify"
    if sub == "commit" and any(commit_con_n(a) for a in resto):
        return "saltear los hooks y checks con --no-verify (-n)"
    if sub == "tag":
        return analizar_tag(resto)
    if sub == "push":
        return analizar_push(resto, cwd, ctx)
    return None


def analizar_tag(args):
    if any(a.split("=")[0] in TAG_LISTAR or re.match(r"^-n\d*$", a) for a in args):
        return None
    if "-d" in args or "--delete" in args:
        return "borrar tags"
    posicionales, i = [], 0
    while i < len(args):
        if args[i] in TAG_CON_VALOR:
            i += 2
            continue
        if not args[i].startswith("-"):
            posicionales.append(args[i])
        i += 1
    return "crear tags" if posicionales else None


def analizar_push(args, cwd, ctx):
    opciones, posicionales, i = set(), [], 0
    while i < len(args):
        a = args[i]
        if a in PUSH_CON_VALOR:
            opciones.add(a)
            i += 2
            continue
        if a.startswith("-"):
            opciones.add(a.split("=")[0])
        else:
            posicionales.append(a)
        i += 1
    for o, que in (("--all", "pushear todas las ramas"), ("--mirror", "pushear todas las ramas"),
                   ("--tags", "pushear tags"), ("--follow-tags", "pushear tags")):
        if o in opciones:
            return que
    borrar = bool(opciones & {"--delete", "-d"})
    # Con --repo el remoto no va entre los posicionales: todos son refspecs.
    refspecs = (posicionales if "--repo" in opciones else posicionales[1:]) or ["HEAD"]
    if "tag" in refspecs:
        return "pushear tags"
    for r in refspecs:
        r = r.lstrip("+")
        origen, destino = r.split(":", 1) if ":" in r else (r, r)
        if "$" in destino or destino in ("HEAD", "@"):
            # Sin poder resolverlo, se supone la rama actual (lo más común: git push origin HEAD).
            destino = ctx.rama(cwd) or ""
        if destino.startswith("refs/tags/") or (not borrar and origen and ctx.tag(origen, cwd)):
            return "pushear tags"
        destino = destino.removeprefix("refs/heads/")
        if destino in TRONCALES:
            return f"borrar la rama troncal {destino}" if borrar else f"pushear a la rama troncal {destino}"
    return None


def metodo_api(args):
    for i, a in enumerate(args):
        if a in ("-X", "--method") and i + 1 < len(args):
            return args[i + 1].upper()
        if a.startswith("--method="):
            return a.split("=", 1)[1].upper()
        if re.match(r"^-X[A-Za-z]+$", a):
            return a[2:].upper()
    if any(re.match(r"^-[fF]", a) or a.startswith(("--field", "--raw-field", "--input")) for a in args):
        return "POST"
    return "GET"


def analizar_gh(args):
    palabras, i = [], 0
    while i < len(args):
        if args[i] in ("-R", "--repo"):
            i += 2
            continue
        if not args[i].startswith("-"):
            palabras.append(args[i])
        i += 1
    if palabras[:2] == ["pr", "merge"]:
        return "mergear un PR"
    if palabras[:2] == ["pr", "review"] and any(a in ("--approve", "-a") for a in args):
        return "aprobar un PR"
    if palabras[:1] == ["release"] and palabras[1:2] and palabras[1] in ("create", "delete", "edit", "upload"):
        return "crear, editar o borrar releases"
    if palabras[:1] == ["api"]:
        texto = " ".join(args)
        if any(m in texto for m in MUTACIONES_GRAPHQL):
            return "mergear o tocar ramas, tags o releases por GraphQL"
        if metodo_api(args) == "GET":
            return None
        if re.search(r"pulls/[^/\s]+/merge\b", texto) or re.search(r"/merges\b", texto):
            return "mergear por la API"
        if re.search(r"/releases\b", texto):
            return "crear, editar o borrar releases"
        if re.search(r"/git/refs\b", texto) and (
                "refs/tags/" in texto or re.search(rf"refs/heads/({TRONCAL_RE})(\s|$)", texto)):
            return "crear tags o mover una rama troncal por la API"
        if re.search(r"/protection\b|/rulesets\b", texto):
            return "cambiar la protección de ramas"
    return None


def analizar(texto, cwd, ctx):
    for sub in sustituciones(texto):
        m = analizar(sub, cwd, ctx)
        if m:
            return m
    for palabras in comandos(texto):
        if palabras[0] == "cd" and len(palabras) > 1:
            destino = os.path.expanduser(os.path.expandvars(palabras[1]))
            if "$" not in destino:
                cwd = os.path.join(cwd or os.getcwd(), destino)
            continue
        # Cualquier git o gh del comando, aunque venga después de env, timeout, sudo, xargs…
        for i, p in enumerate(palabras):
            nombre, resto, m = p.rsplit("/", 1)[-1], palabras[i + 1:], None
            if nombre == "git":
                m = analizar_git(resto, cwd, ctx)
            elif nombre == "gh":
                m = analizar_gh(resto)
            elif nombre in SHELLS:
                j = next((k for k, a in enumerate(resto) if re.match(r"^-[a-zA-Z]*c[a-zA-Z]*$", a)), None)
                if j is not None and j + 1 < len(resto):
                    m = analizar(preparar(resto[j + 1]), cwd, ctx)
            elif nombre == "eval":
                m = analizar(preparar(" ".join(resto)), cwd, ctx)
            if m:
                return m
    return None


def preparar(texto):
    texto = re.sub(r"\\\n", "", texto or "")  # continuaciones de línea
    return sin_comentarios(sacar_heredocs(texto))


def motivo(comando, rama_actual=None, cwd=None, es_tag=None):
    """Por qué hay que frenar el comando, o None si puede correr."""
    ctx = Contexto(rama_actual or rama_de, es_tag or tag_existe, cwd)
    return analizar(preparar(comando), cwd, ctx)


def rama_de(cwd):
    r = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd or None, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def tag_existe(nombre, cwd):
    r = subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{nombre}"], cwd=cwd or None,
                       capture_output=True, text=True)
    return r.returncode == 0


def a_ojo(comando):
    """Último recurso si el análisis falla: buscar los comandos frenados en el texto crudo."""
    patrones = (r"\bgh\b[^\n;&|]*\bpr\s+merge\b", r"\bgh\b[^\n;&|]*\bpr\s+review\b[^\n;&|]*--approve",
                r"\bgh\s+release\s+(create|delete|edit|upload)\b", r"--no-verify\b", r"\bgit\s+tag\s+\S",
                rf"\bgit\b[^\n;&|]*\bpush\b[^\n;&|]*\b({TRONCAL_RE})\b")
    if any(re.search(p, comando) for p in patrones):
        return "un comando que no pude analizar y se parece a uno frenado"
    return None


def como_texto(valor):
    """Un comando como texto: tal cual, o unido si vino como lista; None si es otra cosa."""
    if isinstance(valor, str):
        return valor
    if isinstance(valor, list) and all(isinstance(v, str) for v in valor):
        return " ".join(valor)
    return None


def comando_de(entrada):
    """(comando, herramienta) del hook, o (None, None) si no es un comando de shell.

    Claude Code y Codex: tool_name "Bash" y tool_input.command. Copilot: toolName "bash" y toolArgs
    (objeto o texto JSON). Cursor (beforeShellExecution): command."""
    if not isinstance(entrada, dict):
        return None, None
    if entrada.get("tool_name") == "Bash":
        args = entrada.get("tool_input")
        return como_texto(args.get("command") if isinstance(args, dict) else args), "claude"
    if entrada.get("toolName") == "bash":
        args = entrada.get("toolArgs")
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except ValueError:
                pass  # no es JSON: es el comando mismo
        return como_texto(args.get("command") if isinstance(args, dict) else args), "copilot"
    if entrada.get("hook_event_name") == "beforeShellExecution":
        return como_texto(entrada.get("command")), "cursor"
    return None, None


def main():
    try:
        entrada = json.load(sys.stdin)
    except ValueError:
        return 0  # sin entrada válida no hay comando que frenar
    comando, herramienta = comando_de(entrada)
    if not comando:
        return 0
    try:
        m = motivo(comando, cwd=entrada.get("cwd"))
    except Exception:
        m = a_ojo(comando)
    if not m:
        return 0
    corto = f"Frenado por las barandas de la plantilla (scripts/agentes/barandas.py): {m}."
    texto = (f"{corto}\nAGENTS.md (Autonomía): un agente no mergea, no aprueba PRs, no crea tags ni releases, "
             f"no pushea a ramas troncales y no saltea checks. No busques otro camino: si la persona lo pidió, "
             f"pedile que lo corra ella (en Claude Code, en el chat):\n! {comando.strip()}")
    # Cada herramienta lee el motivo de un lugar distinto: Claude Code y Codex de stderr con exit 2,
    # Copilot del JSON (el exit 2 deniega igual), Cursor del JSON con exit 0.
    if herramienta == "copilot":
        print(json.dumps({"permissionDecision": "deny", "permissionDecisionReason": texto}, ensure_ascii=False))
    elif herramienta == "cursor":
        print(json.dumps({"permission": "deny", "user_message": corto, "agent_message": texto}, ensure_ascii=False))
        return 0
    print(texto, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
