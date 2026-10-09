#!/usr/bin/env python3
"""Pasa un proyecto iniciado con --chico al modo completo de la plantilla.

Uso: python3 scripts/crecer.py [--releases] [--plantilla <url o ruta>]

Clona la plantilla, la inicializa en modo completo con los datos de .agent-kit.json
y, por cada archivo:
  - si el proyecto no lo tiene → lo agrega;
  - si el proyecto lo tiene sin cambios desde el init → lo reemplaza;
  - si el proyecto lo modificó → NO lo pisa: deja la versión completa en
    .agent-kit/pendientes/<ruta> para integrarla a mano (o con la skill update-docs).
No commitea: los cambios quedan en el working tree para revisarlos y abrir un PR.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

PLANTILLA = os.environ.get("AGENT_KIT_PLANTILLA", "https://github.com/lautioliver/agent-kit-template")
NO_TRAER = {"README.md", "README.en.md", ".agent-kit.json", "scripts/crecer.py"}  # el README completo explica la plantilla, no el proyecto
PENDIENTES = ".agent-kit/pendientes"


def salir(msg):
    print(f"crecer.py: {msg}", file=sys.stderr)
    sys.exit(1)


def sh(*cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        salir(f"{' '.join(cmd[:3])}… falló: {(r.stderr or r.stdout).strip()}")
    return r.stdout


def huella(ruta):
    return hashlib.sha1(open(ruta, "rb").read()).hexdigest()


def archivos(raiz):
    for base, dirs, files in os.walk(raiz):
        dirs[:] = [d for d in dirs if d != ".git"]
        for n in files:
            yield os.path.relpath(os.path.join(base, n), raiz)


def main():
    args = sys.argv[1:]
    plantilla = args[args.index("--plantilla") + 1] if "--plantilla" in args else PLANTILLA
    os.chdir(sh("git", "rev-parse", "--show-toplevel").strip())

    if not os.path.exists(".agent-kit.json"):
        salir("no encuentro .agent-kit.json: este repo no se creó con la plantilla (o es anterior a crecer).")
    kit = json.load(open(".agent-kit.json", encoding="utf-8"))
    if kit.get("modo") != "chico":
        salir(f"el proyecto ya está en modo {kit.get('modo')}.")
    if sh("git", "status", "--porcelain").strip():
        salir("hay cambios sin commitear. Commitealos o guardalos antes de crecer.")
    releases = "--releases" in args
    if releases and kit["rama_base"] == "main":
        salir("--releases necesita la rama base develop.")

    tmp = tempfile.mkdtemp(prefix="agent-kit-")
    try:
        print(f"Clonando la plantilla desde {plantilla}…")
        sh("git", "clone", "-q", "--depth", "1", plantilla, tmp)
        init = ["./scripts/init-plantilla.sh", kit["proyecto"], kit["rama_base"]] + (["releases"] if releases else [])
        sh(*init, cwd=tmp)

        agregados, reemplazados, pendientes, iguales = [], [], [], 0
        registradas = kit.get("archivos", {})

        # La arquitectura del modo chico es contenido del proyecto: se mueve a donde la espera el modo completo.
        movido = None
        if os.path.exists("docs/architecture.md") and not os.path.exists("docs/development/architecture.md"):
            os.makedirs("docs/development", exist_ok=True)
            sh("git", "mv", "docs/architecture.md", "docs/development/architecture.md")
            movido = "docs/architecture.md → docs/development/architecture.md"

        for ruta in sorted(archivos(tmp)):
            if ruta in NO_TRAER:
                continue
            origen = os.path.join(tmp, ruta)
            if movido and ruta == "docs/development/architecture.md":
                continue
            if not os.path.exists(ruta):
                os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
                shutil.copy2(origen, ruta)
                agregados.append(ruta)
            elif huella(ruta) == huella(origen):
                iguales += 1
            elif registradas.get(ruta) == huella(ruta):
                shutil.copy2(origen, ruta)
                reemplazados.append(ruta)
            else:
                destino = os.path.join(PENDIENTES, ruta)
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                shutil.copy2(origen, destino)
                pendientes.append(ruta)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # Registro: los archivos que trajo la plantilla quedan como "sin tocar" desde ahora.
    for ruta in agregados + reemplazados:
        registradas[ruta] = huella(ruta)
    if movido:
        registradas.pop("docs/architecture.md", None)
    kit.update({"modo": "completo", "releases": releases, "archivos": dict(sorted(registradas.items()))})
    json.dump(kit, open(".agent-kit.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    os.remove("scripts/crecer.py")

    print(f"\nListo: {len(agregados)} agregados, {len(reemplazados)} reemplazados (no los habías tocado), "
          f"{iguales} ya iguales, {len(pendientes)} pendientes.")
    if movido:
        print(f"Movido: {movido}")
    if pendientes:
        print(f"\nPendientes: los modificaste vos, así que no los pisé. La versión completa está en {PENDIENTES}/:")
        for p in pendientes:
            print(f"  - {p}")
        print("Integrá lo que sirva (por ejemplo, las secciones nuevas de AGENTS.md) y borrá la carpeta .agent-kit/.")
    print("\nPasos siguientes:")
    print("  1. python3 scripts/agentes/check-docs.py → marca las rutas TODO/ de docs/mapa-agentes.json y los")
    print("     links a la arquitectura vieja. Completá el mapa con las rutas reales del proyecto.")
    print("  2. Revisá el diff, commiteá y abrí un PR.")
    print("  3. Después del merge, corré el workflow Labels para crear los labels nuevos.")
    print("  4. Las skills de bloqueos y épicas necesitan sub-issues y dependencias de GitHub habilitadas.")


if __name__ == "__main__":
    main()
