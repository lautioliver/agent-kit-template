---
skill: implement-issue
issue: 61
pr: 67
area: docs
rutas: .claude/skills/implement-issue/rojo.sh, .claude/skills/implement-issue/test-rojo.sh
fecha: 2026-10-09
skill_sha: 52205a9a80bdf6ec85b08807047764bd71f287fa
---
**Desvíos:** el rojo no pasó por rojo.sh (no puede juzgar su propio test: los nombres de los casos coinciden con sus patrones); se corrió test-rojo.sh directo, como en #51.
**Decisiones no cubiertas:** KeyError y TypeError genéricos no van a fallas de carga: salen con 2 por falta de aserción. Se sacó también ✗ además de ×. `assert ` pasó a `^E +assert ` porque la línea `>   assert` del código del test aparece en toda falla de pytest. No se pudo probar con pytest real (no instalado).
**Lo que encontró la revisión:** /code-review (low): nada.
**Propuesta:** que test-rojo.sh no ponga nombres de errores en las descripciones de los casos, así rojo.sh puede validar su propio rojo.
