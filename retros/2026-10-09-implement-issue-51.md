---
skill: implement-issue
issue: 51
pr: 58
area: docs
rutas: .claude/skills/implement-issue/rojo.sh, .claude/skills/implement-issue/test-rojo.sh, docs/mapa-agentes.json
fecha: 2026-10-09
skill_sha: e2b89e006cb208ba7104111766f746c35aa91cea
---
**Desvíos:** el rojo no pasó por rojo.sh: con la versión vieja, el nombre del caso "vitest: Cannot find module" en la salida del test coincidía con la lista negra y salía con 2. Se corrió el test directo.
**Decisiones no cubiertas:** con la lógica nueva, los propios test-*.sh de la plantilla (salida "FAIL - …") salían con 2; se sumó `^FAIL - ` como evidencia de aserción. No se pudo agregar a SKILL.md la línea sobre "falla no reconocida" porque estaba en 120 líneas (#54).
**Lo que encontró la revisión:** /code-review (low): nada.
**Propuesta:** ninguna.
