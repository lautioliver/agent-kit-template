#!/usr/bin/env python3
"""Cruza los archivos cambiados con docs/mapa-agentes.json.

Dice qué documentos revisar y qué rutas sensibles se tocaron.
Uso:
  mapa.py                      # cambios de la rama contra la base (BASE, <RAMA_BASE> o la del remoto)
  mapa.py --base develop       # contra otra base
  mapa.py --pr 42              # archivos de un PR
  mapa.py --json               # salida en JSON
"""
import json
import os
import re
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."


def glob_a_regex(glob):
    """Glob estilo git: ** cruza directorios, * no. Un "?" al principio marca la ruta como
    opcional (check-docs no falla si no existe); para el match se ignora."""
    glob = glob[1:] if glob.startswith("?") else glob
    r, i = "", 0
    while i < len(glob):
        if glob.startswith("**/", i):
            r += "(?:.*/)?"
            i += 3
        elif glob.startswith("**", i):
            r += ".*"
            i += 2
        elif glob[i] == "*":
            r += "[^/]*"
            i += 1
        else:
            r += re.escape(glob[i])
            i += 1
    return re.compile(r + "$")


def coincide(ruta, globs):
    return [g for g in globs if glob_a_regex(g).match(ruta)]


def salir(mensaje):
    """Error explicado, sin traceback: un agente que ve un stack trace tiende a improvisar."""
    print(f"mapa.py: {mensaje}", file=sys.stderr)
    sys.exit(2)


def existe(ref):
    return subprocess.run(["git", "rev-parse", "-q", "--verify", f"{ref}^{{commit}}"],
                          capture_output=True).returncode == 0


def rama_base(args):
    """--base, BASE o el valor que deja el init. En la plantilla sin inicializar (el valor
    sigue siendo un marcador <…>), usa la rama por defecto del remoto y lo avisa."""
    base = args[args.index("--base") + 1] if "--base" in args else os.environ.get("BASE", "<RAMA_BASE>")
    if not base.startswith("<"):
        return base
    r = subprocess.run(["git", "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"],
                       capture_output=True, text=True)
    defecto = r.stdout.strip().removeprefix("origin/")
    if not defecto:
        r = subprocess.run(["git", "ls-remote", "--symref", "origin", "HEAD"], capture_output=True, text=True)
        m = re.search(r"^ref: refs/heads/(\S+)\s+HEAD", r.stdout, re.M)
        defecto = m.group(1) if m else ""
    if not defecto:
        salir(f"la rama base no está configurada ({base}): la plantilla no se inicializó y no pude "
              "leer la rama por defecto de origin. Pasá --base <rama> o definí BASE.")
    print(f"Aviso: la rama base no está configurada ({base}); uso la rama por defecto del remoto, "
          f"{defecto}. Para otra, pasá --base o BASE.", file=sys.stderr)
    return defecto


def archivos_cambiados(args):
    if "--pr" in args:
        n = args[args.index("--pr") + 1]
        r = subprocess.run(["gh", "pr", "diff", n, "--name-only"], capture_output=True, text=True)
        if r.returncode != 0:
            salir(f"no pude leer el PR #{n} ({r.stderr.strip() or 'gh falló'}). ¿Existe y está autenticado gh?")
        return [l for l in r.stdout.splitlines() if l]
    base = rama_base(args)
    ref = f"origin/{base}" if existe(f"origin/{base}") else base
    if not existe(ref):
        salir(f"no encuentro la rama '{base}' ni 'origin/{base}'. "
              f"Corré 'git fetch origin {base}' o pasá --base <rama>.")
    r = subprocess.run(["git", "diff", "--name-only", f"{ref}...HEAD"], capture_output=True, text=True)
    if r.returncode != 0:
        salir(f"git diff contra '{ref}' falló: {r.stderr.strip()}. ¿Tienen historia en común? Probá con --base.")
    out = r.stdout
    sucios = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
    nombres = set(out.splitlines()) | {l[3:].split(" -> ")[-1] for l in sucios.splitlines()}
    return sorted(n for n in nombres if n)


def main():
    args = sys.argv[1:]
    with open(os.path.join(RAIZ, "docs", "mapa-agentes.json")) as f:
        mapa = json.load(f)
    cambiados = archivos_cambiados(args)

    docs = {}
    for regla in mapa.get("docs", []):
        tocados = [a for a in cambiados if coincide(a, regla["cuando"])]
        if not tocados:
            continue
        for d in regla["revisar"]:
            entrada = docs.setdefault(d, {"motivos": [], "archivos": [], "ya_cambiado": d in cambiados})
            if regla["motivo"] not in entrada["motivos"]:
                entrada["motivos"].append(regla["motivo"])
            entrada["archivos"] += [a for a in tocados if a not in entrada["archivos"]]

    sensibles = []
    for s in mapa.get("sensibles", []):
        tocados = [a for a in cambiados if coincide(a, s["rutas"])]
        if tocados:
            sensibles.append({"tipo": s["tipo"], "archivos": tocados, "skill": s.get("skill")})

    if "--json" in args:
        print(json.dumps({"cambiados": cambiados, "docs": docs, "sensibles": sensibles}, ensure_ascii=False, indent=2))
        return

    print(f"Archivos cambiados: {len(cambiados)}")
    print("\n## Docs a revisar")
    if not docs:
        print("_Ninguno según el mapa._")
    for d, e in docs.items():
        estado = "ya modificado en este cambio" if e["ya_cambiado"] else "SIN MODIFICAR"
        print(f"- {d} ({estado}) — {'; '.join(e['motivos'])}: {', '.join(e['archivos'][:5])}")
    print("\n## Rutas sensibles tocadas")
    if not sensibles:
        print("_Ninguna._")
    for s in sensibles:
        extra = f" → usar la skill {s['skill']}" if s["skill"] else ""
        print(f"- {s['tipo']}: {', '.join(s['archivos'][:5])}{extra}")
    if sensibles:
        print("\nTocar rutas sensibles requiere aprobación (AGENTS.md, Autonomía) y correr /security-review.")


if __name__ == "__main__":
    main()
