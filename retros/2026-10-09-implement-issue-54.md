---
skill: implement-issue
issue: 54
pr: 60
area: docs
rutas: .claude/skills/implement-issue/SKILL.md, .claude/skills/implement-issue/preparar.sh, .github/workflows/labels.yml
fecha: 2026-10-09
skill_sha: e2b89e006cb208ba7104111766f746c35aa91cea
---
**Desvíos:** el código de preparar.sh --help se escribió antes que su test; el rojo se comprobó después, contra la versión de HEAD, y el test se commiteó antes que el cambio.
**Decisiones no cubiertas:** en el PR escribí que el check nuevo de labels.yml iba a correr en el propio PR; con pull_request_target corre la versión de la base, así que rige recién después del merge (corregido en el cuerpo). El check de cuerpo se limitó a ramas claude/.
**Lo que encontró la revisión:** /code-review (low): nada.
**Propuesta:** la skill no dice que los cambios a workflows con pull_request_target no se prueban en el propio PR; podría ir a lecciones.md.
