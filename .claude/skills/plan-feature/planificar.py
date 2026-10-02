#!/usr/bin/env python3
"""Crea un plan de trabajo en GitHub: épica, sub-issues y bloqueos entre ellos.

Uso:
  planificar.py plan.json --borrador   # valida y muestra el plan; no crea nada
  planificar.py plan.json              # crea todo (después de confirmar el borrador)
  planificar.py plan.json --repo owner/repo

Formato de plan.json:
{
  "epica": {"titulo": "...", "cuerpo": "...", "labels": ["tipo:feature", "area:api"]},
  "issues": [
    {"clave": "schema", "titulo": "...", "cuerpo": "...", "labels": ["tipo:task"]},
    {"clave": "migracion", "titulo": "...", "cuerpo": "...", "labels": ["tipo:task"],
     "bloqueado_por": ["schema", 25], "motivo": "necesita la tabla nueva"}
  ]
}
- "epica" es opcional. Si está, cada issue queda como sub-issue de la épica.
- "bloqueado_por" acepta claves del mismo plan o números de issues que ya existen.
"""
import json
import os
import subprocess
import sys
import tempfile


def gh(*args, entrada=None):
    r = subprocess.run(["gh", *args], capture_output=True, text=True, input=entrada)
    if r.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:3])}…: {r.stderr.strip()}")
    return r.stdout.strip()


def gh_json(*args):
    return json.loads(gh(*args) or "null")


def labels_validos():
    """Lee los nombres de .github/labels.yml (si existe) sin depender de PyYAML."""
    raiz = gh_raiz()
    ruta = os.path.join(raiz, ".github", "labels.yml")
    if not os.path.exists(ruta):
        return None
    nombres = set()
    with open(ruta) as f:
        for linea in f:
            linea = linea.strip()
            if linea.startswith("- name:"):
                nombres.add(linea.split(":", 1)[1].strip().strip('"').strip("'"))
    return nombres


def gh_raiz():
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return r.stdout.strip() or "."


def orden_topologico(issues):
    """Ordena para que cada issue venga después de sus bloqueantes. Falla si hay ciclo."""
    claves = {i["clave"] for i in issues}
    pendientes = {i["clave"]: {b for b in i.get("bloqueado_por", []) if b in claves} for i in issues}
    orden = []
    while pendientes:
        listos = sorted(c for c, deps in pendientes.items() if not deps)
        if not listos:
            ciclo = ", ".join(sorted(pendientes))
            raise ValueError(f"hay un ciclo de bloqueos entre: {ciclo}")
        for c in listos:
            orden.append(c)
            del pendientes[c]
        for deps in pendientes.values():
            deps.difference_update(listos)
    por_clave = {i["clave"]: i for i in issues}
    return [por_clave[c] for c in orden]


def validar(plan, obtener_repo):
    errores, avisos = [], []
    issues = plan.get("issues", [])
    if not issues:
        errores.append("el plan no tiene issues")
    claves = [i.get("clave") for i in issues]
    if any(not c for c in claves):
        errores.append("todos los issues necesitan una clave")
    duplicadas = {c for c in claves if claves.count(c) > 1}
    if duplicadas:
        errores.append(f"claves repetidas: {', '.join(sorted(duplicadas))}")

    validos = labels_validos()
    externos = {}
    todos = ([plan["epica"]] if plan.get("epica") else []) + issues
    for i in todos:
        nombre = i.get("clave", "épica")
        if not i.get("titulo"):
            errores.append(f"{nombre}: falta el título")
        tipos = [l for l in i.get("labels", []) if l.startswith("tipo:")]
        if len(tipos) != 1:
            errores.append(f"{nombre}: tiene que tener exactamente un label tipo: (tiene {len(tipos)})")
        if validos is not None:
            for l in i.get("labels", []):
                if l not in validos:
                    errores.append(f"{nombre}: el label {l} no está en .github/labels.yml")
        for b in i.get("bloqueado_por", []):
            if isinstance(b, int):
                if b not in externos:
                    try:
                        externos[b] = gh_json("api", f"repos/{obtener_repo()}/issues/{b}")
                    except RuntimeError:
                        errores.append(f"{nombre}: el issue #{b} no existe")
                        continue
                if externos[b]["state"] != "open":
                    avisos.append(f"{nombre}: #{b} ya está cerrado, no se crea ese bloqueo")
            elif b not in claves:
                errores.append(f"{nombre}: bloqueado por '{b}', que no es una clave del plan")

    orden = []
    # El ciclo se busca aunque haya otros errores, para mostrarlos todos de una vez.
    if issues and all(claves) and not duplicadas:
        try:
            orden = orden_topologico(issues)
        except ValueError as e:
            errores.append(str(e))
    return orden, externos, errores, avisos


def bloqueantes_abiertos(issue, externos):
    return [b for b in issue.get("bloqueado_por", [])
            if not isinstance(b, int) or externos[b]["state"] == "open"]


def mostrar_borrador(plan, orden, externos, avisos):
    if plan.get("epica"):
        e = plan["epica"]
        print(f"Épica: {e['titulo']}  [{', '.join(e.get('labels', []))}]\n")
    print("Issues, en el orden en que se pueden hacer:\n")
    for n, i in enumerate(orden, 1):
        labels = list(i.get("labels", []))
        bloq = bloqueantes_abiertos(i, externos)
        if bloq and "estado:bloqueado" not in labels:
            labels.append("estado:bloqueado")
        print(f"{n}. [{i['clave']}] {i['titulo']}  [{', '.join(labels)}]")
        if bloq:
            nombres = [f"#{b}" if isinstance(b, int) else b for b in bloq]
            motivo = f" — {i['motivo']}" if i.get("motivo") else ""
            print(f"   bloqueado por: {', '.join(nombres)}{motivo}")
    for a in avisos:
        print(f"\nAviso: {a}")


def crear_issue(repo, titulo, cuerpo, labels):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(cuerpo)
        ruta = f.name
    try:
        args = ["issue", "create", "-R", repo, "--title", titulo, "--body-file", ruta]
        for l in labels:
            args += ["--label", l]
        url = gh(*args)
    finally:
        os.unlink(ruta)
    numero = int(url.rstrip("/").rsplit("/", 1)[1])
    return numero, url


def firma():
    try:
        return f"\n\n_Abierto desde el chat con Claude Code a pedido de @{gh('api', 'user', '-q', '.login')}._"
    except RuntimeError:
        return ""


def crear(plan, orden, externos, repo):
    creados = {}  # clave -> (numero, url)
    ids = {}      # numero -> id interno
    pie = firma()

    def id_de(numero):
        if numero not in ids:
            ids[numero] = gh_json("api", f"repos/{repo}/issues/{numero}")["id"]
        return ids[numero]

    try:
        epica = None
        if plan.get("epica"):
            e = plan["epica"]
            epica = crear_issue(repo, e["titulo"], e.get("cuerpo", "") + pie, e.get("labels", []))
            print(f"Épica #{epica[0]}: {epica[1]}")

        for i in orden:
            bloq = bloqueantes_abiertos(i, externos)
            numeros = [b if isinstance(b, int) else creados[b][0] for b in bloq]
            labels = list(i.get("labels", []))
            cuerpo = i.get("cuerpo", "")
            if numeros:
                if "estado:bloqueado" not in labels:
                    labels.append("estado:bloqueado")
                motivo = f": {i['motivo']}" if i.get("motivo") else ""
                cuerpo += f"\n\nBloqueado por {', '.join(f'#{n}' for n in numeros)}{motivo}"
            numero, url = crear_issue(repo, i["titulo"], cuerpo + pie, labels)
            creados[i["clave"]] = (numero, url)
            if epica:
                gh("api", f"repos/{repo}/issues/{epica[0]}/sub_issues", "-X", "POST",
                   "-F", f"sub_issue_id={id_de(numero)}")
            for n in numeros:
                gh("api", f"repos/{repo}/issues/{numero}/dependencies/blocked_by", "-X", "POST",
                   "-F", f"issue_id={id_de(n)}")
            extra = f" (bloqueado por {', '.join(f'#{n}' for n in numeros)})" if numeros else ""
            print(f"#{numero} {i['titulo']}{extra}: {url}")
    except RuntimeError as err:
        print(f"\nError: {err}", file=sys.stderr)
        if creados:
            hechos = ", ".join(f"#{n}" for n, _ in creados.values())
            print(f"Se alcanzaron a crear: {hechos}. Revisalos antes de reintentar.", file=sys.stderr)
        sys.exit(1)


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print(__doc__)
        sys.exit(2)
    borrador = "--borrador" in args
    try:
        with open(args[0]) as f:
            plan = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"No pude leer el plan {args[0]}: {e}", file=sys.stderr)
        sys.exit(1)

    # GitHub se consulta solo si hace falta: issues externos en bloqueado_por, o al crear.
    repo_cache = []

    def obtener_repo():
        if not repo_cache:
            try:
                repo_cache.append(args[args.index("--repo") + 1] if "--repo" in args else
                                  gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"))
            except RuntimeError as e:
                print(f"No pude identificar el repo de GitHub ({e}). Pasá --repo owner/repo.", file=sys.stderr)
                sys.exit(1)
        return repo_cache[0]

    orden, externos, errores, avisos = validar(plan, obtener_repo)
    if errores:
        print("El plan no es válido:", file=sys.stderr)
        for e in errores:
            print(f"- {e}", file=sys.stderr)
        sys.exit(1)
    if borrador:
        mostrar_borrador(plan, orden, externos, avisos)
    else:
        crear(plan, orden, externos, obtener_repo())


if __name__ == "__main__":
    main()
