---
skill: implement-issue
issue: 34
pr: 47
area: docs
rutas: .claude/agents/, docs/agentes/contrato-subagentes.md, scripts/agentes/check-docs.py, scripts/agentes/test-agentes.sh, docs/mapa-agentes.json, AGENTS.md, README.md
modelo: opus
rol: sesion
fecha: 2026-10-09
skill_sha: 52205a9a80bdf6ec85b08807047764bd71f287fa
---
**Desvíos:** se implementó en paralelo con #35 (Haiku, como subagente) usando `preparar.sh --worktree` del PR #40 todavía sin mergear, corrido desde el checkout de esa rama. El contrato de salida quedó en un archivo propio (`docs/agentes/contrato-subagentes.md`) en vez de repetido en los tres agentes. Un test se ajustó después del rojo (el revisor pasó a tener `Write`) porque lo pidió la autorevisión.
**Decisiones no cubiertas:** `model: inherit` se rechaza a propósito. El control temprano de escalado no puede usar `mapa.py` (solo compara la rama con la base): se compara contra `sensibles` del mapa.
**Lo que encontró la revisión:** `/code-review`: 10 hallazgos, 4 de ellos hacían que los agentes no pudieran cumplir su prompt (mapa.py sin archivos, cwd reseteado, revisor sin fetch ni Write, revisor en el worktree del implementador). Un test con `check | grep -q` bajo `pipefail` daba falso negativo.
**Propuesta:** una lección: "los prompts de subagentes se revisan contra lo que las herramientas y scripts realmente permiten"; y un helper común de asserts para los tests en bash (hoy copiado en tres archivos).
