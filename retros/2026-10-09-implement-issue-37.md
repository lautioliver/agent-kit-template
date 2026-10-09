---
skill: implement-issue
issue: 37
pr: 68
area: docs
rutas: .claude/skills/orquestar/, .claude/agents/revisor.md, .claude/skills/implement-issue/SKILL.md, .gitignore, docs/agentes/contrato-subagentes.md
fecha: 2026-10-09
skill_sha: 706ecda8629f42c447b50671a3f4e154704ba3e8
modelo: opus
rol: sesion
---
**Desvíos:** el título del primer commit en rojo pasaba de 72 y se corrigió con amend antes de pushear. Los stubs de ruteo.py y limpiar.sh se agregaron después de ver que el rojo inicial era "archivo inexistente".
**Decisiones no cubiertas:** lo mecánico del orquestador (ruteo y limpieza) pasó a scripts testeables en vez de texto; el flujo de la skill queda sin test (es un prompt) y lo valida #38. El gh falso de los tests ignora -q, así que los scripts leen JSON con jq.
**Lo que encontró la revisión:** /code-review (medium) encontró 9 hallazgos reales: rutas sensibles sin barra y doble tipo en ruteo.py, push sin upstream tras quitar -u, contradicción con el contrato, errores de gh tragados en limpiar.sh, mapa incompleto. Todos corregidos con test en rojo propio.
**Propuesta:** en lecciones: al sacar `-u` de un push, revisar todos los pushes posteriores de las skills y agentes (la rama queda sin upstream).
