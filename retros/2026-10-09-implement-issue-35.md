---
skill: implement-issue
issue: 35
pr: 46
area: docs
rutas: .claude/skills/mejorar-skills/plantilla-retro.md, .claude/skills/mejorar-skills/retro.sh, .claude/skills/mejorar-skills/SKILL.md, .claude/skills/mejorar-skills/test-retros.sh
modelo: haiku
rol: implementador-liviano
fecha: 2026-10-09
skill_sha: 52205a9a80bdf6ec85b08807047764bd71f287fa
agente_sha: desconocido
---
**Desvíos:** se saltó el paso 1 (preparar.sh) por instrucción del orquestador; el issue ya estaba tomado en el worktree. Lint, typecheck y tests quedan sin configurar en la plantilla: el PR lo dice. El título usa el scope `docs` del §2 de la convención (`feat(docs): ...`), no el formato `tipo: descripción` del pedido, porque `pr-title.yml` exige Conventional Commits con scope.
**Decisiones no cubiertas:** `modelo` y `rol` no se validan contra la lista (texto libre); `corrida:` se acepta en cualquier skill, no solo en orquestar; `agente_sha` queda en `desconocido` hasta que exista `.claude/agents/` (issue #34).
**Lo que encontró la revisión:** la autorevisión (diff completo, shellcheck, mapa.py) no encontró bugs. Casos borde leídos y cubiertos: frontmatter con valor vacío (`modelo:` sin valor se conserva tal cual), reintento de pendientes que ya traen los campos.
**Propuesta:** en #34, validar `rol` contra la lista de subagentes que existen y decidir si `modelo` vacío cuenta como `desconocido`.
