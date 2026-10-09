---
skill: implement-issue
issue: 35
pr: 46
area: docs
rutas: .claude/skills/mejorar-skills/retro.sh, .claude/skills/mejorar-skills/test-retros.sh, .claude/skills/mejorar-skills/plantilla-retro.md, .claude/skills/mejorar-skills/SKILL.md
fecha: 2026-10-09
skill_sha: 52205a9a80bdf6ec85b08807047764bd71f287fa
modelo: haiku
rol: implementador-liviano
agente_sha: desconocido
---
**Desvíos:** en la primera ronda el título del PR usó el scope `docs` por una justificación falsa (dije que pr-title.yml exigía scope; tiene requireScope false). Corregido el texto del PR; el título queda igual. Además el primer cuerpo del PR decía 62 líneas en SKILL.md y son 64.
**Decisiones no cubiertas:** el test de corrida mal formada con pr válido ya pasaba antes del arreglo; se dejó como guardia y se dice en el PR.
**Lo que encontró la revisión:** campos vacíos y espacios al final (modelo/rol no normalizados, agente_sha perdido con rol con espacio); corrida aceptada fuera de orquestar. Los cuatro hallazgos se corrigieron con test rojo previo.
**Propuesta:** en la autorevisión, correr los tests con un frontmatter de casos vacíos y espacios antes de abrir el PR, no solo los casos del criterio.
