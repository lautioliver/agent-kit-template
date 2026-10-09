#!/usr/bin/env python3
"""Última guardia antes del PR: según lo que cambió, decide qué verificar y lo corre.

Las verificaciones se configuran en la sección "verificar" de docs/mapa-agentes.json:
  {"nombre": "tests", "siempre": true, "correr": "npm test"}
  {"nombre": "migraciones", "cuando": ["db/schema/**"], "correr": "…"}
Una verificación corre si es "siempre" o si algún archivo cambiado coincide con "cuando".
En "correr" se pueden usar {base} (la referencia de la rama base, p. ej. origin/main)
y {archivos} (los archivos cambiados que coinciden, entre comillas).
Un "correr" que empieza con "TODO" se informa como sin configurar y no se ejecuta.

Uso:
  verificar.py                 # contra la rama base (BASE, <RAMA_BASE> o la del remoto)
  verificar.py --base develop
  verificar.py --listar        # muestra qué correría, sin correr nada
Sale con 1 si alguna verificación falla.
"""
import json
import os
import shlex
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mapa import RAIZ, archivos_cambiados, coincide, existe, rama_base  # noqa: E402


def referencia_base(args, base):
    return f"origin/{base}" if existe(f"origin/{base}") else base


def main():
    args = sys.argv[1:]
    os.chdir(RAIZ)
    ruta_mapa = os.path.join(RAIZ, "docs", "mapa-agentes.json")
    if not os.path.exists(ruta_mapa):
        print("verificar.py: no hay docs/mapa-agentes.json.", file=sys.stderr)
        sys.exit(2)
    reglas = json.load(open(ruta_mapa, encoding="utf-8")).get("verificar", [])
    if not reglas:
        print("verificar.py: el mapa no tiene sección 'verificar'.", file=sys.stderr)
        sys.exit(2)

    rama = rama_base(args)
    if "--base" in args:  # se reemplaza por la resuelta, para no avisar dos veces
        i = args.index("--base")
        args = args[:i] + args[i + 2:]
    args += ["--base", rama]
    cambiados = archivos_cambiados(args)  # sale con un mensaje claro si la base no existe
    base = referencia_base(args, rama)

    plan = []
    for r in reglas:
        # En las que corren siempre (sin "cuando"), {archivos} son todos los cambiados.
        tocados = [a for a in cambiados if coincide(a, r["cuando"])] if r.get("cuando") else list(cambiados)
        if r.get("siempre") or tocados:
            motivo = "siempre" if r.get("siempre") and not r.get("cuando") else f"{len(tocados)} archivo(s): {', '.join(tocados[:3])}"
            cmd = r["correr"].replace("{base}", base).replace("{archivos}", " ".join(shlex.quote(a) for a in tocados))
            plan.append((r["nombre"], motivo, cmd))

    print(f"Cambios contra {base}: {len(cambiados)} archivo(s). Verificaciones: {len(plan)}.\n")
    if "--listar" in args:
        for nombre, motivo, cmd in plan:
            print(f"- {nombre} ({motivo})\n    {cmd}")
        return

    resultados = []
    for nombre, motivo, cmd in plan:
        if cmd.startswith("TODO"):
            resultados.append((nombre, "sin configurar", 0))
            continue
        print(f"▶ {nombre} ({motivo})\n  $ {cmd}", flush=True)
        t0 = time.time()
        ok = subprocess.run(cmd, shell=True).returncode == 0
        resultados.append((nombre, "ok" if ok else "FALLÓ", time.time() - t0))
        print(flush=True)

    print("Resultado:")
    for nombre, estado, seg in resultados:
        print(f"  {estado:15} {nombre}" + (f" ({seg:.0f}s)" if seg else ""))
    sin_config = [n for n, e, _ in resultados if e == "sin configurar"]
    if any(e == "FALLÓ" for _, e, _ in resultados):
        print("\nHay verificaciones que fallan: corregilas antes de abrir el PR. No las desactives.")
        sys.exit(1)
    if sin_config:
        print(f"\nPasó lo configurado, pero {', '.join(sin_config)} no se verificó: falta el comando en "
              "docs/mapa-agentes.json. No digas que el cambio está verificado.")
        return
    print("\nTodo verificado.")


if __name__ == "__main__":
    main()
