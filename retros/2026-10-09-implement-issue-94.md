---
skill: implement-issue
issue: 94
pr: 99
area: area:infra
rutas: scripts/actualizar.py, scripts/init-plantilla.sh, scripts/crecer.py, scripts/test-actualizar.sh
fecha: 2026-10-09
skill_sha: 1da16c8487540d9f07bdfe696e319bf138ca3d67
modelo: opus
rol: sesion
---
**Desvíos:** ninguno.
**Decisiones no cubiertas:** si la versión debe avanzar cuando hay conflictos, y qué versión registra un proyecto creado desde `main` después de un tag.
**Lo que encontró la revisión:** `/code-review` encontró 10 problemas: se podía volver a una versión más vieja, quedaban pendientes viejos, rompía con versiones con sufijo y con rutas relativas, ignoraba los cambios de permisos, y un proyecto creado después del tag se trataba como modificado.
**Propuesta:** ninguna.
