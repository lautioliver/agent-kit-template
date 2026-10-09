#!/usr/bin/env python3
"""Barandas: hook PreToolUse de Claude Code que frena, antes de correrlos, los comandos que un
agente nunca corre solo (AGENTS.md, Autonomía → Nunca): mergear o aprobar PRs, pushear a una rama
troncal, crear tags o releases, tocar la protección de ramas y saltear checks con --no-verify.

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
SEPARADORES = {";", "&&", "||", "|", "&", "(", ")", "\n", "|&", ";;"}
ENVOLTORIOS = {"command", "builtin", "exec", "nohup", "time", "sudo", "nice"}
SHELLS = {"bash", "sh", "zsh", "dash"}
GIT_OPC_CON_VALOR = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
TAG_LISTAR = {"-l", "--list", "--contains", "--no-contains", "--points-at", "--merged", "--no-merged",
              "-v", "--verify"}
MUTACIONES_GRAPHQL = ("mergePullRequest", "enablePullRequestAutoMerge", "mergeBranch", "createRef",
                      "createRelease", "deleteBranchProtectionRule", "updateBranchProtectionRule")


def sacar_heredocs(texto):
    """El cuerpo de un heredoc es texto, no comandos: se saca antes de analizar."""
    lineas, fuera, fin = texto.split("\n"), [], None
    for linea in lineas:
        if fin is not None:
            if linea.strip() == fin:
                fin = None
            continue
        fuera.append(linea)
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", linea)
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
    """Parte una línea de shell en comandos simples (listas de palabras)."""
    lex = shlex.shlex(texto.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = ""
    actual = []
    for tok in lex:
        if tok in SEPARADORES or set(tok) <= set(";&|()"):
            if actual:
                yield actual
            actual = []
        else:
            actual.append(tok)
    if actual:
        yield actual


def sin_envoltorios(palabras):
    """Saca asignaciones (A=1), env, xargs y similares hasta llegar al comando real."""
    i = 0
    while i < len(palabras):
        p = palabras[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", p) or p in ENVOLTORIOS:
            i += 1
        elif p in ("env", "xargs"):
            i += 1
            while i < len(palabras) and (palabras[i].startswith("-") or "=" in palabras[i]):
                i += 1
        else:
            break
    return palabras[i:]


def analizar_git(args, cwd, rama_actual):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] == "-C" and i + 1 < len(args):
            cwd = args[i + 1]
        i += 2 if args[i] in GIT_OPC_CON_VALOR else 1
    if i >= len(args):
        return None
    sub, resto = args[i], args[i + 1:]
    if "--no-verify" in resto or (sub == "commit" and any(re.match(r"^-[a-zA-Z]*n", a) for a in resto)):
        return "saltear los hooks y checks con --no-verify"
    if sub == "tag":
        if any(a.split("=")[0] in TAG_LISTAR or a.startswith("-n") for a in resto):
            return None
        if "-d" in resto or "--delete" in resto or any(not a.startswith("-") for a in resto):
            return "crear o borrar tags"
        return None
    if sub == "push":
        return analizar_push(resto, cwd, rama_actual)
    return None


def analizar_push(args, cwd, rama_actual):
    opciones = {a for a in args if a.startswith("-")}
    for o, que in (("--all", "pushear todas las ramas"), ("--mirror", "pushear todas las ramas"),
                   ("--tags", "pushear tags"), ("--follow-tags", "pushear tags")):
        if o in opciones:
            return que
    borrar = "--delete" in opciones or "-d" in opciones
    posicionales = [a for a in args if not a.startswith("-")]
    refspecs = posicionales[1:]
    if not refspecs:
        refspecs = ["HEAD"]
    for r in refspecs:
        r = r.lstrip("+")
        destino = r.split(":", 1)[1] if ":" in r else r
        if destino in ("HEAD", "@") or (not destino and not borrar and ":" not in r):
            destino = rama_actual(cwd) or ""
        if destino.startswith("refs/tags/"):
            return "pushear tags"
        if re.match(r"^v\d+(\.\d+)*", destino) and not borrar:
            return "pushear tags"
        destino = destino.removeprefix("refs/heads/")
        if destino in TRONCALES:
            return f"pushear a la rama troncal {destino}" if not borrar else f"borrar la rama troncal {destino}"
    return None


def metodo_api(args):
    for i, a in enumerate(args):
        if a in ("-X", "--method") and i + 1 < len(args):
            return args[i + 1].upper()
        if a.startswith("--method="):
            return a.split("=", 1)[1].upper()
    if any(a in ("-f", "-F", "--field", "--raw-field", "--input") or a.startswith(("--field=", "--raw-field="))
           for a in args):
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
        if re.search(r"/git/refs\b", texto) and "refs/tags/" in texto:
            return "crear tags"
        if re.search(r"/protection\b|/rulesets\b", texto):
            return "cambiar la protección de ramas"
    return None


def motivo(comando, rama_actual=None, cwd=None, es_tag=None):
    """Por qué hay que frenar el comando, o None si puede correr."""
    if rama_actual is None:
        rama_actual = rama_de
    texto = sacar_heredocs(comando or "")
    for sub in sustituciones(texto):
        m = motivo(sub, rama_actual, cwd)
        if m:
            return m
    try:
        lista = list(comandos(texto))
    except ValueError:  # comillas sin cerrar: el shell tampoco lo va a correr
        return None
    for palabras in lista:
        palabras = sin_envoltorios(palabras)
        if not palabras:
            continue
        cmd, args = palabras[0].rsplit("/", 1)[-1], palabras[1:]
        if cmd == "cd" and args:
            cwd = os.path.join(cwd or os.getcwd(), os.path.expanduser(args[0]))
        elif cmd in SHELLS and "-c" in args and args.index("-c") + 1 < len(args):
            m = motivo(args[args.index("-c") + 1], rama_actual, cwd)
        elif cmd == "eval":
            m = motivo(" ".join(args), rama_actual, cwd)
        elif cmd == "git":
            m = analizar_git(args, cwd, rama_actual)
        elif cmd == "gh":
            m = analizar_gh(args)
        else:
            m = None
        if cmd != "cd" and m:
            return m
    return None


def rama_de(cwd):
    r = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd or None, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def main():
    try:
        entrada = json.load(sys.stdin)
    except ValueError:
        return 0  # sin entrada válida no hay comando que frenar
    if entrada.get("tool_name") != "Bash":
        return 0
    comando = (entrada.get("tool_input") or {}).get("command", "")
    m = motivo(comando, cwd=entrada.get("cwd"))
    if not m:
        return 0
    print(f"Frenado por las barandas de la plantilla (scripts/agentes/barandas.py): {m}.\n"
          f"AGENTS.md (Autonomía): un agente no mergea, no aprueba PRs, no crea tags ni releases, no pushea a "
          f"ramas troncales y no saltea checks. Si la persona lo pidió, pedile que lo corra ella en el chat:\n"
          f"! {comando.strip()}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
