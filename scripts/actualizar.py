#!/usr/bin/env python3
"""Trae una versión nueva de la plantilla al proyecto.

Uso: python3 scripts/actualizar.py [--version vX.Y.Z] [--plantilla <url o ruta>]

Clona la plantilla, la inicializa con los datos de .agent-kit.json (mismo modo, rama base y
fecha) en la versión pedida (por defecto, el último tag vX.Y.Z; sin tags, la rama por defecto) y
también en la versión de origen del proyecto. Por cada archivo de la plantilla:
  - si el proyecto no lo tiene → lo agrega (salvo que lo haya borrado el proyecto);
  - si el proyecto no lo tocó → lo reemplaza;
  - si lo tocó → lo fusiona con `git merge-file` contra la versión de origen. Si la fusión tiene
    conflictos, NO lo pisa: deja el resultado con marcas en .agent-kit/pendientes/<ruta>;
  - si la plantilla lo sacó → lo borra si el proyecto no lo tocó; si lo tocó, avisa.
Sin versión de origen (proyectos anteriores a las versiones) no puede fusionar: lo modificado va
entero a .agent-kit/pendientes/, como hace crecer.py.
No commitea: los cambios quedan en el working tree para revisarlos y abrir un PR.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

PLANTILLA = os.environ.get("AGENT_KIT_PLANTILLA", "https://github.com/lautioliver/barrilete-kit")
# Del proyecto, aunque la plantilla también los tenga: el README de la plantilla la explica a ella.
NO_TRAER = {"README.md", "README.en.md", ".agent-kit.json", ".github/equipo.json"}
PENDIENTES = ".agent-kit/pendientes"


def salir(msg):
    print(f"actualizar.py: {msg}", file=sys.stderr)
    sys.exit(1)


def sh(*cmd, cwd=None, env=None, ok=(0,)):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env)
    if r.returncode not in ok:
        salir(f"{' '.join(cmd[:3])}… falló: {(r.stderr or r.stdout).strip()}")
    return r


def huella(ruta):
    with open(ruta, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def archivos(raiz):
    for base, dirs, files in os.walk(raiz):
        dirs[:] = [d for d in dirs if d != ".git"]
        for n in files:
            yield os.path.relpath(os.path.join(base, n), raiz)


def version_de(tag):
    m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
    return tuple(int(x) for x in m.groups()) if m else None


def tags(clon):
    nombres = sh("git", "tag", "--list", "v*", cwd=clon).stdout.split()
    return sorted((t for t in nombres if version_de(t)), key=version_de)


def inicializar(clon, ref, destino, kit):
    """La plantilla en `ref`, inicializada con los datos del proyecto, en `destino`."""
    os.makedirs(destino)
    tar = subprocess.run(["git", "archive", ref], cwd=clon, capture_output=True)
    if tar.returncode != 0:
        salir(f"no encuentro {ref} en la plantilla: {tar.stderr.decode().strip()}")
    subprocess.run(["tar", "-xf", "-"], cwd=destino, input=tar.stdout, check=True)
    sh("git", "init", "-q", cwd=destino)
    args = ["./scripts/init-plantilla.sh", kit["proyecto"], kit["rama_base"]]
    if kit.get("releases"):
        args.append("releases")
    if kit.get("modo") == "chico":
        args.append("--chico")
    env = dict(os.environ, AGENT_KIT_FECHA=kit.get("fecha", ""))
    sh(*args, cwd=destino, env=env)
    with open(os.path.join(destino, ".agent-kit.json"), encoding="utf-8") as f:
        return json.load(f)


def changelog(clon, ref, desde):
    """Las secciones de CHANGELOG.md más nuevas que `desde`."""
    r = subprocess.run(["git", "show", f"{ref}:CHANGELOG.md"], cwd=clon, capture_output=True, text=True)
    if r.returncode != 0:
        return ""
    secciones = re.split(r"(?m)^(?=## )", r.stdout)
    nuevas = []
    for s in secciones:
        m = re.match(r"## \[?v?(\d+)\.(\d+)\.(\d+)", s)
        if m and (desde is None or tuple(map(int, m.groups())) > desde):
            nuevas.append(s.rstrip())
    return "\n\n".join(nuevas)


def fusionar(proyecto, base, nueva):
    """git merge-file: (texto fusionado, hay_conflictos)."""
    r = subprocess.run(["git", "merge-file", "-p", "-L", "proyecto", "-L", "versión anterior", "-L",
                        "versión nueva", proyecto, base, nueva], capture_output=True)
    if r.returncode < 0 or r.returncode > 127:
        return None, True
    return r.stdout, r.returncode != 0


def main():
    args = sys.argv[1:]
    plantilla = args[args.index("--plantilla") + 1] if "--plantilla" in args else PLANTILLA
    pedida = args[args.index("--version") + 1] if "--version" in args else None
    os.chdir(sh("git", "rev-parse", "--show-toplevel").stdout.strip())

    if not os.path.exists(".agent-kit.json"):
        salir("no encuentro .agent-kit.json: este repo no se creó con la plantilla (o es anterior a ese registro).")
    with open(".agent-kit.json", encoding="utf-8") as f:
        kit = json.load(f)
    if sh("git", "status", "--porcelain").stdout.strip():
        salir("hay cambios sin commitear. Commitealos o guardalos antes de actualizar.")
    actual = kit.get("version")

    tmp = tempfile.mkdtemp(prefix="agent-kit-")
    try:
        clon = os.path.join(tmp, "clon")
        print(f"Clonando la plantilla desde {plantilla}…")
        sh("git", "clone", "-q", plantilla, clon)
        disponibles = tags(clon)
        if pedida:
            ref = pedida if pedida.startswith("v") else f"v{pedida}"
            if ref not in disponibles:
                salir(f"la plantilla no tiene la versión {ref}. Versiones: {', '.join(disponibles) or 'ninguna'}.")
        else:
            ref = disponibles[-1] if disponibles else "HEAD"
        r = subprocess.run(["git", "show", f"{ref}:VERSION"], cwd=clon, capture_output=True, text=True)
        objetivo = r.stdout.strip() if r.returncode == 0 else None
        if objetivo and objetivo == actual and ref != "HEAD":
            print(f"El proyecto ya está en la versión {actual} de la plantilla. Nada que actualizar.")
            return

        nueva = os.path.join(tmp, "nueva")
        inicializar(clon, ref, nueva, kit)
        base = None
        if actual and f"v{actual}" in disponibles:
            base = os.path.join(tmp, "base")
            inicializar(clon, f"v{actual}", base, kit)

        registradas = kit.get("archivos", {})
        agregados, reemplazados, fusionados, conflictos, pendientes = [], [], [], [], []
        borrados, conservados, saltados, iguales = [], [], [], 0
        en_nueva = set(archivos(nueva)) - NO_TRAER

        def sin_tocar(ruta):
            """El proyecto tiene el archivo igual que como lo dejó la plantilla de origen."""
            if base:
                origen = os.path.join(base, ruta)
                return os.path.exists(origen) and huella(origen) == huella(ruta)
            return registradas.get(ruta) == huella(ruta)

        for ruta in sorted(en_nueva):
            nuevo = os.path.join(nueva, ruta)
            origen = os.path.join(base, ruta) if base else None
            if not os.path.exists(ruta):
                if (origen and os.path.exists(origen)) or ruta in registradas:
                    saltados.append(ruta)  # lo borró el proyecto: no se vuelve a traer
                    continue
                os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
                shutil.copy2(nuevo, ruta)
                agregados.append(ruta)
            elif huella(ruta) == huella(nuevo):
                iguales += 1
            elif sin_tocar(ruta):
                shutil.copy2(nuevo, ruta)
                reemplazados.append(ruta)
            elif origen and os.path.exists(origen):
                texto, conflicto = fusionar(ruta, origen, nuevo)
                if texto is not None and not conflicto:
                    with open(ruta, "wb") as f:
                        f.write(texto)
                    fusionados.append(ruta)
                else:
                    destino = os.path.join(PENDIENTES, ruta)
                    os.makedirs(os.path.dirname(destino), exist_ok=True)
                    if texto is None:
                        shutil.copy2(nuevo, destino)
                    else:
                        with open(destino, "wb") as f:
                            f.write(texto)
                    conflictos.append(ruta)
            else:
                destino = os.path.join(PENDIENTES, ruta)
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                shutil.copy2(nuevo, destino)
                pendientes.append(ruta)

        # Lo que la plantilla sacó: estaba en la versión de origen (o en el registro) y ya no está.
        antes = set(archivos(base)) if base else set(registradas)
        for ruta in sorted(antes - en_nueva - NO_TRAER):
            if not os.path.exists(ruta):
                continue
            if sin_tocar(ruta):
                os.remove(ruta)
                borrados.append(ruta)
            else:
                conservados.append(ruta)

        notas = changelog(clon, ref, tuple(map(int, actual.split("."))) if actual else None)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    for ruta in agregados + reemplazados:
        registradas[ruta] = huella(ruta)
    for ruta in borrados:
        registradas.pop(ruta, None)
    kit["archivos"] = dict(sorted(registradas.items()))
    if objetivo:
        kit["version"] = objetivo
    with open(".agent-kit.json", "w", encoding="utf-8") as f:
        json.dump(kit, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"\nListo: de {actual or 'una versión sin número'} a {objetivo or ref}.")
    print(f"  {len(agregados)} agregados, {len(reemplazados)} reemplazados (no los habías tocado), "
          f"{len(fusionados)} fusionados, {iguales} ya iguales, {len(borrados)} borrados.")
    for titulo, lista in (("Fusionados (revisá el diff)", fusionados),
                          ("Con conflictos: no los pisé, la fusión con marcas está en " + PENDIENTES, conflictos),
                          ("Modificados por vos, sin versión de origen para fusionar: la versión nueva está en "
                           + PENDIENTES, pendientes),
                          ("La plantilla los sacó, pero los modificaste: decidí si los borrás", conservados),
                          ("Los habías borrado y la plantilla los cambió: no los traje", saltados)):
        if lista:
            print(f"\n{titulo}:")
            for ruta in lista:
                print(f"  - {ruta}")
    if notas:
        print(f"\nQué cambió en la plantilla:\n\n{notas}")
    print("\nPasos siguientes:")
    print(f"  1. Integrá lo de {PENDIENTES}/ (si hay) y borrá la carpeta .agent-kit/.")
    print("  2. python3 scripts/agentes/check-docs.py, y revisá el diff.")
    print("  3. Commiteá y abrí un PR. Si cambió .github/labels.yml, después del merge corré el workflow Labels.")


if __name__ == "__main__":
    main()
