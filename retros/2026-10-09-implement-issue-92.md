---
skill: implement-issue
issue: 92
pr: 97
area: area:infra
rutas: scripts/agentes/barandas.py, .claude/settings.json, AGENTS.md, README.md
fecha: 2026-10-09
skill_sha: 1da16c8487540d9f07bdfe696e319bf138ca3d67
modelo: opus
rol: sesion
---
**Desvíos:** ninguno en el flujo. La prueba de punta a punta con `claude -p` la agregué yo; la skill no la pide.
**Decisiones no cubiertas:** si un hook que falla tiene que dejar pasar o frenar. Elegí dejar pasar, con un análisis por patrones como último recurso.
**Lo que encontró la revisión:** `/code-review` encontró 10 huecos de parseo de shell (un apóstrofo en un comentario desactivaba todo, `bash -lc`, `-XPUT`, y otros). Después, en #95, una prueba real mostró que Claude Code no carga `.claude/settings.json` si se lanza desde un subdirectorio.
**Propuesta:** `implement-issue` podría pedir una prueba real, y no solo unit tests, cuando el cambio es un hook o la configuración de la herramienta. Esas pruebas no deben usar comandos con efectos reales (como `git push`): usar algo inofensivo, como `gh pr merge` de un PR que no existe.
