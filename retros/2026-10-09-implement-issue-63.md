---
skill: implement-issue
issue: 63
pr: 66
area: docs
rutas: scripts/agentes/check-docs.py, scripts/init-plantilla.sh, scripts/test-init.sh
fecha: 2026-10-09
skill_sha: 52205a9a80bdf6ec85b08807047764bd71f287fa
---
**Desvíos:** un PR para dos issues (#63 y #64), los dos sobre el init y test-init.sh. El primer commit en rojo no se hizo porque un heredoc anidado (<<'PY' dentro de <<'PY') rompió el comando entero; el test se commiteó solo después, antes del arreglo, con el rojo ya visto contra HEAD.
**Decisiones no cubiertas:** cómo detectar una negación en AGENTS.md; quedó por frase.
**Lo que encontró la revisión:** /code-review (low) encontró que la primera versión salteaba la línea entera con una negación y dejaba de validar `.env*` en una línea mixta. Se corrigió con test en rojo propio.
**Propuesta:** en lecciones.md: al editar scripts que contienen heredocs, escribir el script de edición en un archivo en vez de un heredoc anidado. Y armar los cuerpos de PR con sustituciones resueltas antes (se publicó un cuerpo con `$(…)` literal y hubo que editarlo).
