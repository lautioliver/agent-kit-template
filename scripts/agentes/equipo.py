#!/usr/bin/env python3
"""Equipo del proyecto (.github/equipo.json) y a quién asignar cada issue.

Uso:
  equipo.py listar
  equipo.py agregar <login> [--nombre "Nombre"] [--areas area:api,area:docs] [--forzar]
                                 # agrega o edita; valida el usuario y su acceso al repo
  equipo.py quitar <login>
  equipo.py pausar <login>       # deja de recibir issues (vacaciones, otra prioridad)
  equipo.py activar <login>
  equipo.py sugerir [--labels tipo:bug,area:api] [--carga ana=2,bruno=0]
                                 # imprime el login a asignar, o nada si no hay equipo

Regla de asignación (elegir): entre los integrantes activos, los que cubren alguna
area: del issue; si nadie la cubre (o el issue no tiene area:), todos los activos.
Gana el de menos issues abiertos asignados; empate, el primero del archivo.
"""
import json
import os
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
ARCHIVO = os.path.join(RAIZ, ".github", "equipo.json")
AYUDA = ("Integrantes del equipo para asignar issues. Lo leen solo los scripts que crean issues "
         "(crear-issue, planificar.py). Se edita con /add-member y /remove-member "
         "(scripts/agentes/equipo.py). areas: labels area: de .github/labels.yml que cubre cada uno.")


def elegir(integrantes, labels, carga):
    activos = [i for i in integrantes if i.get("activo", True)]
    if not activos:
        return None
    areas = {l for l in labels if l.startswith("area:")}
    del_area = [i for i in activos if areas & set(i.get("areas", []))]
    candidatos = del_area or activos
    # min() es estable: ante empate queda el primero del archivo.
    return min(candidatos, key=lambda i: carga.get(i["login"], 0))["login"]


def salir(msg, codigo=1):
    print(f"equipo.py: {msg}", file=sys.stderr)
    sys.exit(codigo)


def gh(*args):
    return subprocess.run(["gh", *args], capture_output=True, text=True)


def leer():
    if not os.path.exists(ARCHIVO):
        return {"_ayuda": AYUDA, "integrantes": []}
    return json.load(open(ARCHIVO, encoding="utf-8"))


def guardar(datos):
    os.makedirs(os.path.dirname(ARCHIVO), exist_ok=True)
    with open(ARCHIVO, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=2)
        f.write("\n")


def areas_validas():
    ruta = os.path.join(RAIZ, ".github", "labels.yml")
    if not os.path.exists(ruta):
        return None
    nombres = set()
    for linea in open(ruta, encoding="utf-8"):
        linea = linea.strip()
        if linea.startswith("- name:"):
            nombres.add(linea.split(":", 1)[1].strip().strip('"').strip("'"))
    return {n for n in nombres if n.startswith("area:")}


def opcion(args, nombre):
    if nombre in args:
        i = args.index(nombre)
        if i + 1 >= len(args):
            salir(f"falta el valor de {nombre}")
        return args[i + 1]
    return None


def carga_actual(logins):
    """Issues abiertos asignados a cada uno (la carga que equilibra la asignación)."""
    repo = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").stdout.strip()
    carga = {}
    for login in logins:
        r = gh("issue", "list", "-R", repo, "--state", "open", "--assignee", login,
               "--limit", "500", "--json", "number", "-q", "length")
        carga[login] = int(r.stdout.strip() or 0) if r.returncode == 0 else 0
    return carga


def cmd_listar(datos):
    integrantes = datos["integrantes"]
    if not integrantes:
        print("El equipo está vacío. Agregá integrantes con /add-member.")
        return
    carga = carga_actual([i["login"] for i in integrantes])
    for i in integrantes:
        estado = "activo" if i.get("activo", True) else "pausado"
        areas = ", ".join(i.get("areas", [])) or "todas"
        print(f"- @{i['login']} ({i.get('nombre') or 'sin nombre'}) · {estado} · áreas: {areas} · "
              f"{carga[i['login']]} issue(s) abiertos")


def cmd_agregar(datos, args):
    if not args or args[0].startswith("--"):
        salir("uso: equipo.py agregar <login> [--nombre N] [--areas a,b] [--forzar]")
    login = args[0].lstrip("@")
    if gh("api", f"users/{login}", "-q", ".login").returncode != 0:
        salir(f"no existe el usuario de GitHub @{login}.")
    repo = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").stdout.strip()
    if gh("api", f"repos/{repo}/collaborators/{login}").returncode != 0 and "--forzar" not in args:
        salir(f"@{login} no tiene acceso a {repo}: GitHub no deja asignarle issues. "
              "Invitalo primero (o usá --forzar si la invitación está pendiente).")
    areas = opcion(args, "--areas")
    lista = [a.strip() for a in areas.split(",") if a.strip()] if areas else None
    if lista is not None:
        validas = areas_validas()
        malas = [a for a in lista if not a.startswith("area:") or (validas is not None and a not in validas)]
        if malas:
            salir(f"áreas que no están en .github/labels.yml: {', '.join(malas)}. "
                  f"Válidas: {', '.join(sorted(validas or [])) or 'ninguna'}.")
    existente = next((i for i in datos["integrantes"] if i["login"].lower() == login.lower()), None)
    if existente:
        if opcion(args, "--nombre") is not None:
            existente["nombre"] = opcion(args, "--nombre")
        if lista is not None:
            existente["areas"] = lista
        print(f"Actualizado @{login}.")
    else:
        datos["integrantes"].append({
            "login": login, "nombre": opcion(args, "--nombre") or "", "areas": lista or [], "activo": True,
        })
        print(f"Agregado @{login}.")
    guardar(datos)


def buscar(datos, login):
    login = login.lstrip("@").lower()
    i = next((i for i in datos["integrantes"] if i["login"].lower() == login), None)
    if not i:
        salir(f"@{login} no está en el equipo.")
    return i


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    cmd, resto = args[0], args[1:]
    datos = leer()
    datos.setdefault("_ayuda", AYUDA)
    datos.setdefault("integrantes", [])

    if cmd == "listar":
        cmd_listar(datos)
    elif cmd == "agregar":
        cmd_agregar(datos, resto)
    elif cmd in ("quitar", "pausar", "activar"):
        if not resto:
            salir(f"uso: equipo.py {cmd} <login>")
        i = buscar(datos, resto[0])
        if cmd == "quitar":
            datos["integrantes"].remove(i)
        else:
            i["activo"] = cmd == "activar"
        guardar(datos)
        print({"quitar": "Quitado", "pausar": "Pausado", "activar": "Activado"}[cmd] + f" @{i['login']}.")
        if cmd == "quitar":
            print("Sus issues abiertos siguen asignados: reasignalos si hace falta "
                  f"(gh issue list --assignee {i['login']}).")
    elif cmd == "sugerir":
        labels = [l for l in (opcion(resto, "--labels") or "").split(",") if l]
        integrantes = datos["integrantes"]
        if opcion(resto, "--carga") is not None:
            carga = {k: int(v) for k, v in (p.split("=") for p in opcion(resto, "--carga").split(",") if p)}
        else:
            carga = carga_actual([i["login"] for i in integrantes if i.get("activo", True)])
        elegido = elegir(integrantes, labels, carga)
        if elegido:
            print(elegido)
    else:
        salir(f"comando desconocido: {cmd}", 2)


if __name__ == "__main__":
    main()
