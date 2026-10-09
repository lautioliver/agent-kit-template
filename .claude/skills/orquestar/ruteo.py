#!/usr/bin/env python3
"""Qué implementador le toca a un issue: la regla de ruteo de la épica #33 (decisión 2).

Haiku solo si el issue es tipo:docs o tipo:task, sin logica-negocio ni breaking-change y sin
rutas sensibles (docs/mapa-agentes.json) nombradas en el título o el cuerpo. Lo demás, Sonnet.
Si después Haiku encuentra rutas sensibles con mapa.py, escala (implementador-liviano.md).

Uso: ruteo.py <n°issue>
Imprime el modelo (haiku o sonnet) en la primera línea y el motivo en la segunda.
"""
import json
import os
import re
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
sys.path.insert(0, os.path.join(RAIZ, "scripts", "agentes"))

LIVIANOS = {"tipo:docs", "tipo:task"}
RIESGO = {"logica-negocio", "breaking-change"}


def salir(mensaje):
    print(f"ruteo.py: {mensaje}", file=sys.stderr)
    sys.exit(2)


def sensibles_nombradas(texto, mapa):
    """Rutas del texto (con o sin backticks) que caen en una ruta sensible del mapa. Cuenta cada
    palabra, tenga o no "/" (package.json, Dockerfile), una carpeta sin barra final (src/auth),
    una ruta con "./" adelante o dentro de un link (…/blob/main/src/auth/x.ts), sin distinguir
    mayúsculas. Equivocarse hacia Sonnet está bien: "infra" en prosa también cuenta."""
    from mapa import glob_a_regex
    palabras = {c.rstrip(".,;:") for c in re.findall(r"[\w.-]+(?:/[\w.-]*)*", texto)} - {""}
    hallazgos = []
    for s in mapa.get("sensibles", []):
        regex = [re.compile(glob_a_regex(g).pattern, re.I) for g in s.get("rutas", [])]
        for palabra in sorted(palabras):
            partes = palabra.removeprefix("./").split("/")
            # La ruta entera y cada sufijo después de una "/" (cubre los links a GitHub).
            sufijos = ["/".join(partes[i:]) for i in range(len(partes))]
            if any(r.match(c) or r.match(c.rstrip("/") + "/x") for c in sufijos if c for r in regex):
                hallazgos.append(f"{palabra} ({s.get('tipo', 'sensible')})")
    return hallazgos


def main():
    if len(sys.argv) != 2 or not sys.argv[1].lstrip("#").isdigit():
        salir("uso: ruteo.py <n°issue>")
    n = sys.argv[1].lstrip("#")
    r = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
                       capture_output=True, text=True)
    repo = r.stdout.strip()
    if r.returncode != 0 or not repo:
        salir(f"no pude leer el repo de GitHub ({r.stderr.strip() or 'gh falló'}). ¿Hay un remoto y gh está autenticado?")
    r = subprocess.run(["gh", "api", f"repos/{repo}/issues/{n}"], capture_output=True, text=True)
    if r.returncode != 0:
        salir(f"no pude leer el issue #{n} ({r.stderr.strip() or 'gh falló'}).")
    issue = json.loads(r.stdout)
    labels = {l["name"] if isinstance(l, dict) else l for l in issue.get("labels", [])}

    tipo = sorted(l for l in labels if l.startswith("tipo:"))
    if not tipo or not set(tipo) <= LIVIANOS:
        return print("sonnet", f"motivo: {', '.join(tipo) or 'sin tipo:'} no es solo tipo:docs o tipo:task", sep="\n")
    riesgo = sorted(RIESGO & labels)
    if riesgo:
        return print("sonnet", f"motivo: lleva {', '.join(riesgo)}", sep="\n")
    ruta_mapa = os.path.join(RAIZ, "docs", "mapa-agentes.json")
    if not os.path.exists(ruta_mapa):
        return print("sonnet", "motivo: no hay docs/mapa-agentes.json para descartar rutas sensibles", sep="\n")
    with open(ruta_mapa, encoding="utf-8") as f:
        mapa = json.load(f)
    nombradas = sensibles_nombradas(f"{issue.get('title', '')}\n{issue.get('body') or ''}", mapa)
    if nombradas:
        return print("sonnet", f"motivo: nombra rutas sensibles: {', '.join(nombradas)}", sep="\n")
    print("haiku", f"motivo: {', '.join(tipo)} sin logica-negocio, breaking-change ni rutas sensibles nombradas", sep="\n")


if __name__ == "__main__":
    main()
