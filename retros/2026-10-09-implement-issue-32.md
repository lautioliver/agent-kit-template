---
skill: implement-issue
issue: 32
pr: 39
area: docs
rutas: .claude/skills/mejorar-skills/, docs/agentes/lecciones.md, scripts/agentes/check-docs.py
fecha: 2026-10-09
skill_sha: 68718ec
---
**Desvíos:** preparar.sh falló con `<RAMA_BASE>` sin reemplazar (este repo es la plantilla); se corrió con `BASE=main`. El test de retros se reescribió después del commit rojo para cumplir shellcheck (se comprobó que seguía en rojo contra los scripts viejos).
**Decisiones no cubiertas:** el nombre `agentes/retros` no encaja en la convención de ramas; quedó como pregunta en el PR. Cómo testear scripts de shell sin framework de tests: remoto bare local + `gh` falso + shim de git para simular la carrera.
**Lo que encontró la revisión:** `/code-review` encontró 10 puntos; 6 reales (ruta relativa tras el `cd`, review-pr sin issue, reintento ante cualquier error de push, SHA corto en consolidado, update-ref local sin compare-and-swap, carrera sin test), corregidos con tests en rojo primero.
**Propuesta:** que `preparar.sh` y `verificar.py` detecten `<RAMA_BASE>` sin reemplazar y caigan en la rama por defecto del remoto con un aviso.
