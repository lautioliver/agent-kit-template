#!/usr/bin/env python3
"""Valida la documentación como infraestructura para agentes. Sale con 1 si hay errores.

Revisa:
- Links relativos de Markdown ([texto](ruta)) que apuntan a archivos inexistentes.
- Rutas entre backticks (`dir/archivo.ext`) cuyo primer directorio existe pero el archivo no.
- Menciones a ADR-NNN sin archivo en docs/decisions/.
- ADRs que no figuran en docs/README.md o docs/llms.txt.
- Documentos obligatorios y rutas de docs/mapa-agentes.json que no existen.
- Rutas de ejemplo (TODO/…) que quedaron en docs/mapa-agentes.json después del init.
"""
import json
import os
import re
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
os.chdir(RAIZ)

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
BACKTICK = re.compile(r"`(\.?[\w.-]+(?:/[\w.-]+)+)`")
ADR = re.compile(r"\bADR-(\d{3})\b")
EXT = re.compile(r"\.(md|txt|ya?ml|json|sh|py|ts|tsx|js|mjs|sql|toml)$")
IGNORAR_DIRS = {".git", "node_modules", ".turbo", ".next", "dist", "build", ".pnpm-store"}

errores = []


def md_files():
    for base, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in IGNORAR_DIRS and not d.startswith(".claude/worktrees")]
        if "/.claude/worktrees" in base:
            continue
        for f in files:
            if f.endswith(".md") or f == "llms.txt":
                yield os.path.normpath(os.path.join(base, f))


def sin_codigo(texto):
    """Quita bloques ``` para no validar ejemplos."""
    return re.sub(r"```.*?```", "", texto, flags=re.S)


adrs = {m.group(1): f for f in os.listdir("docs/decisions") if (m := re.match(r"ADR-(\d{3})-", f))} \
    if os.path.isdir("docs/decisions") else {}

for archivo in md_files():
    with open(archivo, encoding="utf-8") as fh:
        texto = sin_codigo(fh.read())
    carpeta = os.path.dirname(archivo)
    for n, linea in enumerate(texto.splitlines(), 1):
        prosa = re.sub(r"`[^`]*`", "", linea)  # links y ADRs dentro de `código` son ejemplos
        for destino in LINK.findall(prosa):
            if re.match(r"^[a-z]+:", destino) or destino.startswith("#") or "<" in destino:
                continue
            ruta = destino.split("#")[0]
            if ruta and not os.path.exists(os.path.normpath(os.path.join(carpeta, ruta))):
                errores.append(f"{archivo}:{n}: link roto → {destino}")
        for ruta in BACKTICK.findall(linea):
            if "*" in ruta or not EXT.search(ruta):
                continue
            primero = ruta.lstrip("./").split("/")[0]
            if os.path.isdir(primero) and not os.path.exists(ruta) \
                    and not os.path.exists(os.path.join(carpeta, ruta)):
                errores.append(f"{archivo}:{n}: ruta inexistente → `{ruta}`")
        for num in set(ADR.findall(prosa)):
            if num != "000" and num not in adrs:
                errores.append(f"{archivo}:{n}: ADR-{num} no existe en docs/decisions/")

for indice in ("docs/README.md", "docs/llms.txt"):
    if os.path.exists(indice):
        contenido = open(indice, encoding="utf-8").read()
        for num, f in adrs.items():
            if num != "000" and f not in contenido:
                errores.append(f"{indice}: falta el ADR {f} en el índice")

if os.path.exists("docs/mapa-agentes.json"):
    mapa = json.load(open("docs/mapa-agentes.json", encoding="utf-8"))
    for f in mapa.get("obligatorios", []):
        if not os.path.exists(f):
            errores.append(f"docs/mapa-agentes.json: falta el documento obligatorio {f}")
    # Después del init (el script se borra solo), un "TODO/" en el mapa es una ruta que no existe:
    # el agente nunca marcaría nada como sensible. En la plantilla sin inicializar se permite.
    if not os.path.exists("scripts/init-plantilla.sh"):
        crudo = open("docs/mapa-agentes.json", encoding="utf-8").read()
        pendientes = sorted(set(re.findall(r'"(TODO/[^"]*)"', crudo)))
        if pendientes:
            errores.append("docs/mapa-agentes.json: completá las rutas de ejemplo con las reales del proyecto: "
                           + ", ".join(pendientes))
    for regla in mapa.get("docs", []):
        for f in regla.get("revisar", []):
            if not os.path.exists(f):
                errores.append(f"docs/mapa-agentes.json: '{regla.get('motivo')}' apunta a {f}, que no existe")

errores = list(dict.fromkeys(errores))
if errores:
    print(f"Documentación con {len(errores)} problema(s):")
    for e in errores:
        print(f"- {e}")
    sys.exit(1)
print("Documentación OK.")
