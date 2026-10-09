---
skill: implement-issue
issue: 71
pr: sin PR
area: docs
rutas: ninguna (solo lectura de .github/workflows/docs.yml)
fecha: 2026-10-09
skill_sha: 706ecda8629f42c447b50671a3f4e154704ba3e8
modelo: haiku
rol: implementador-liviano
agente_sha: 2e5e060c70127bf8d257e2194ebe43285b11bca0
---
**Desvíos:** escalé sin tocar archivos porque el criterio exige editar .github/workflows/docs.yml (CI, regla 3 de escalado). No pregunté a la persona antes de empezar, como pide el paso 2 de la skill; la pregunta quedó en el issue, que es lo que indica el contrato para subagentes.

**Decisiones no cubiertas:** si el mapa marcaba la ruta como sensible antes de editar. No lo corrí sobre un cambio real para no tocar el CI solo para probar el mapa; `mapa.py` sobre el worktree limpio dio exit 0 y sin rutas sensibles.

**Lo que encontró la revisión:** nada (no hubo revisión).

**Propuesta:** para issues de docs que solo comentan un archivo, el mapa podría avisar en el momento de elegirlos que el archivo es CI, así el liviano no llega a leerlo.
