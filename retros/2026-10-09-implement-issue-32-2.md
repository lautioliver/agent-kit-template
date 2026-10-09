---
skill: implement-issue
issue: 32
pr: 39
area: docs
rutas: .claude/skills/mejorar-skills/retro.sh, AGENTS.md, docs/convencion-nombres-github.md
fecha: 2026-10-09
skill_sha: 68718ece2d4145980fe1de112d18ee0d12e0fb59
---
**Desvíos:** correcciones post-revisión en el mismo PR, a pedido del usuario. Un push falló en CI por shellcheck: el local (más nuevo) reporta SC2329 y el de CI SC2317 para el mismo caso.
**Decisiones no cubiertas:** la excepción de rama `agentes/retros` en AGENTS.md y la convención (confirmada por el usuario). Marcar lo consolidado al abrir el PR y no al mergear (se mantuvo).
**Lo que encontró la revisión:** /review-pr (otra sesión) encontró 4 a corregir y 6 sugerencias; uno era falso (commit-tree no respeta commit.gpgSign en git 2.50), comprobado antes de arreglarlo.
**Propuesta:** fijar la versión de shellcheck en docs.yml o que verificar.py avise cuando la local difiere de la de CI.
