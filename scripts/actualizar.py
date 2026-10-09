#!/usr/bin/env python3
"""Trae una versión nueva de la plantilla al proyecto.

Uso: python3 scripts/actualizar.py [--version vX.Y.Z] [--plantilla <url o ruta>]

Clona la plantilla, la inicializa con los datos de .agent-kit.json (mismo modo, rama base y
fecha) en la versión pedida (por defecto, el último tag vX.Y.Z; sin tags, la rama por defecto) y
también en la versión de origen del proyecto. Por cada archivo de la plantilla:
  - si el proyecto no lo tiene → lo agrega (salvo que lo haya borrado el proyecto);
  - si el proyecto no lo tocó → lo reemplaza (contenido y permisos);
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
import stat
import subprocess
import sys
import tempfile

PLANTILLA = os.environ.get("AGENT_KIT_PLANTILLA", "https://github.com/lautioliver/barrilete-kit")
# Del proyecto, aunque la plantilla también los tenga: el README de la plantilla la explica a ella.
NO_TRAER = {"README.md", "README.en.md", ".agent-kit.json", ".github/equipo.json"}
PENDIENTES = ".agent-kit/pendientes"
USO = "Uso: python3 scripts/actualizar.py [--version vX.Y.Z] [--plantilla <url o ruta>]"


def salir(msg):
    print(f"actualizar.py: {msg}", file=sys.stderr)
    sys.exit(1)


def sh(*cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        salir(f"{' '.join(cmd[:3])}… falló: {(r.stderr or r.stdout).strip()}")
    return r


def huella(ruta):
    with open(ruta, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def ejecutable(ruta):
    return bool(os.stat(ruta).st_mode & stat.S_IXUSR)


def archivos(raiz):
    for base, dirs, files in os.walk(raiz):
        dirs[:] = [d for d in dirs if d != ".git"]
        for n in files:
            yield os.path.relpath(os.path.join(base, n), raiz)


def numero(version):
    """(X, Y, Z) de "X.Y.Z" o "vX.Y.Z", ignorando sufijos como -rc.1; None si no se entiende."""
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)", version or "")
    return tuple(int(x) for x in m.groups()) if m else None


def opcion(args, nombre):
    if nombre not in args:
        return None
    i = args.index(nombre)
    if i + 1 >= len(args) or args[i + 1].startswith("--"):
        salir(f"{nombre} necesita un valor.\n{USO}")
    return args[i + 1]


def tags(clon):
    nombres = sh("git", "tag", "--list", "v*", cwd=clon).stdout.split()
    return sorted((t for t in nombres if re.fullmatch(r"v\d+\.\d+\.\d+", t)), key=numero)


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
    sh(*args, cwd=destino, env=dict(os.environ, AGENT_KIT_FECHA=kit.get("fecha", "")))


def changelog(clon, ref, desde):
    """Las secciones de CHANGELOG.md más nuevas que `desde`."""
    r = subprocess.run(["git", "show", f"{ref}:CHANGELOG.md"], cwd=clon, capture_output=True, text=True)
    if r.returncode != 0:
        return ""
    nuevas = []
    for s in re.split(r"(?m)^(?=## )", r.stdout):
        n = numero(s[3:].strip("[ ")) if s.startswith("## ") else None
        if n and (desde is None or n > desde):
            nuevas.append(s.rstrip())
    return "\n\n".join(nuevas)


def fusionar(proyecto, base, nueva):
    """git merge-file: (texto fusionado o None si no se puede, hay_conflictos)."""
    r = subprocess.run(["git", "merge-file", "-p", "-L", "proyecto", "-L", "versión anterior", "-L",
                        "versión nueva", proyecto, base, nueva], capture_output=True)
    if r.returncode < 0 or r.returncode > 127:  # binarios o error: 255
        return None, True
    return r.stdout, r.returncode != 0


def planear(nueva, base, registradas):
    """Qué hacer con cada archivo, sin tocar nada todavía: lista de (acción, ruta, dato)."""
    en_nueva = set(archivos(nueva)) - NO_TRAER

    def sin_tocar(ruta):
        """Igual que como lo dejó la plantilla: en la versión de origen o al crear el proyecto (que
        puede ser posterior al tag, si se creó desde main)."""
        if registradas.get(ruta) == huella(ruta):
            return True
        origen = os.path.join(base, ruta) if base else None
        return bool(origen and os.path.exists(origen) and huella(origen) == huella(ruta))

    plan = []
    for ruta in sorted(en_nueva):
        nuevo = os.path.join(nueva, ruta)
        origen = os.path.join(base, ruta) if base else None
        if not os.path.lexists(ruta):
            # Lo tuvo el proyecto (registro) y ya no: lo borró a propósito.
            plan.append(("saltar" if ruta in registradas else "agregar", ruta, None))
        elif not os.path.isfile(ruta):
            plan.append(("conflicto", ruta, None))  # en el proyecto es un directorio u otra cosa
        elif huella(ruta) == huella(nuevo):
            if ejecutable(ruta) != ejecutable(nuevo) and sin_tocar(ruta):
                plan.append(("permisos", ruta, None))
            else:
                plan.append(("igual", ruta, None))
        elif sin_tocar(ruta):
            plan.append(("reemplazar", ruta, None))
        elif origen and os.path.exists(origen):
            texto, conflicto = fusionar(ruta, origen, nuevo)
            plan.append(("conflicto" if conflicto else "fusionar", ruta, texto))
        else:
            plan.append(("pendiente", ruta, None))
    # Lo que la plantilla sacó: estaba en la versión de origen o en el registro, y ya no está.
    antes = (set(archivos(base)) if base else set()) | set(registradas)
    for ruta in sorted(antes - en_nueva - NO_TRAER):
        if os.path.isfile(ruta):
            plan.append(("borrar" if sin_tocar(ruta) else "conservar", ruta, None))
    return plan


def aplicar(plan, nueva):
    """Aplica el plan. Un error en un archivo no corta el resto: queda anotado."""
    hechos, errores = {}, []
    for accion, ruta, texto in plan:
        nuevo = os.path.join(nueva, ruta)
        try:
            if accion in ("agregar", "reemplazar"):
                os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
                shutil.copy2(nuevo, ruta)
            elif accion == "permisos":
                shutil.copymode(nuevo, ruta)
            elif accion == "fusionar":
                with open(ruta, "wb") as f:
                    f.write(texto)
                shutil.copymode(nuevo, ruta)
            elif accion in ("conflicto", "pendiente"):
                destino = os.path.join(PENDIENTES, ruta)
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                if texto is None:
                    shutil.copy2(nuevo, destino)
                else:
                    with open(destino, "wb") as f:
                        f.write(texto)
            elif accion == "borrar":
                os.remove(ruta)
        except OSError as e:
            errores.append(f"{ruta}: {e}")
            continue
        hechos.setdefault(accion, []).append(ruta)
    return hechos, errores


def main():
    args = sys.argv[1:]
    plantilla = opcion(args, "--plantilla") or PLANTILLA
    if os.path.exists(plantilla):  # una ruta local, relativa a donde se corrió
        plantilla = os.path.abspath(plantilla)
    pedida = opcion(args, "--version")
    os.chdir(sh("git", "rev-parse", "--show-toplevel").stdout.strip())

    if not os.path.exists(".agent-kit.json"):
        salir("no encuentro .agent-kit.json: este repo no se creó con la plantilla (o es anterior a ese registro).")
    with open(".agent-kit.json", encoding="utf-8") as f:
        kit = json.load(f)
    if sh("git", "status", "--porcelain").stdout.strip():
        salir("hay cambios sin commitear. Commitealos o guardalos antes de actualizar.")
    if os.path.isdir(PENDIENTES) and any(archivos(PENDIENTES)):
        salir(f"quedan archivos en {PENDIENTES}/ de una actualización anterior. Integralos y borrá la carpeta "
              "antes de actualizar de nuevo.")
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
        if numero(objetivo) and numero(actual):
            if numero(objetivo) < numero(actual):
                salir(f"{ref} ({objetivo}) es más vieja que la versión del proyecto ({actual}). "
                      "actualizar.py no vuelve atrás.")
            if objetivo == actual and ref != "HEAD":
                print(f"El proyecto ya está en la versión {actual} de la plantilla. Nada que actualizar.")
                return
        notas = changelog(clon, ref, numero(actual))

        nueva = os.path.join(tmp, "nueva")
        inicializar(clon, ref, nueva, kit)
        base = None
        if actual and f"v{actual}" in disponibles:
            base = os.path.join(tmp, "base")
            inicializar(clon, f"v{actual}", base, kit)

        registradas = kit.get("archivos", {})
        plan = planear(nueva, base, registradas)
        hechos, errores = aplicar(plan, nueva)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    for accion in ("agregar", "reemplazar", "permisos"):
        for ruta in hechos.get(accion, []):
            registradas[ruta] = huella(ruta)
    for ruta in hechos.get("borrar", []):
        registradas.pop(ruta, None)
    kit["archivos"] = dict(sorted(registradas.items()))
    if objetivo:
        kit["version"] = objetivo
    with open(".agent-kit.json", "w", encoding="utf-8") as f:
        json.dump(kit, f, ensure_ascii=False, indent=2)
        f.write("\n")

    n = {a: len(hechos.get(a, [])) for a in ("agregar", "reemplazar", "permisos", "fusionar", "igual", "borrar")}
    print(f"\nListo: de {actual or 'una versión sin número'} a {objetivo or ref}.")
    print(f"  {n['agregar']} agregados, {n['reemplazar'] + n['permisos']} reemplazados (no los habías tocado), "
          f"{n['fusionar']} fusionados, {n['igual']} ya iguales, {n['borrar']} borrados.")
    for titulo, accion in (("Fusionados (revisá el diff)", "fusionar"),
                           (f"Con conflictos: no los pisé, la fusión con marcas está en {PENDIENTES}/", "conflicto"),
                           ("Modificados por vos, sin versión de origen para fusionar: la versión nueva está en "
                            f"{PENDIENTES}/", "pendiente"),
                           ("La plantilla los sacó, pero los modificaste: decidí si los borrás", "conservar"),
                           ("Los habías borrado y la plantilla los cambió: no los traje", "saltar")):
        if hechos.get(accion):
            print(f"\n{titulo}:")
            for ruta in hechos[accion]:
                print(f"  - {ruta}")
    if errores:
        print("\nNo pude aplicar (el resto sí se aplicó):")
        for e in errores:
            print(f"  - {e}")
    if notas:
        print(f"\nQué cambió en la plantilla:\n\n{notas}")
    print("\nPasos siguientes:")
    if hechos.get("conflicto") or hechos.get("pendiente"):
        print(f"  1. Integrá ahora lo de {PENDIENTES}/ y borrá la carpeta. La próxima actualización parte de la")
        print(f"     versión {objetivo or ref}: lo que no integres de esta no vuelve a aparecer.")
    else:
        print("  1. Nada pendiente para integrar a mano.")
    print("  2. python3 scripts/agentes/check-docs.py, y revisá el diff.")
    print("  3. Commiteá y abrí un PR. Si cambió .github/labels.yml, después del merge corré el workflow Labels.")


if __name__ == "__main__":
    main()
