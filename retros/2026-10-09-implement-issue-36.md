---
skill: implement-issue
issue: 36
pr: 40
area: infra
rutas: .claude/skills/implement-issue/preparar.sh, .claude/skills/implement-issue/test-preparar.sh, .claude/skills/implement-issue/SKILL.md, docs/mapa-agentes.json
fecha: 2026-10-09
skill_sha: c0f18aa0bc83d88013b628856909e8b6b1ac67e6
---
**Desvíos:** se corrió `preparar.sh 36` sin `--worktree` en el checkout principal (todavía no existía). La skill cargada al empezar era la versión anterior al merge de #39 (decía "issue fijado" para la retro); se siguió la de `main` (`retro.sh` a `agentes/retros`). `<RAMA_BASE>` sigue sin reemplazar en la plantilla: hubo que pasar `BASE=main` a `preparar.sh` y `verificar.py`.
**Decisiones no cubiertas:** dos cambios en el modo sin `--worktree` (rama en otro worktree → falla antes de asignar; número de issue no numérico → uso), aunque el issue decía "sin cambios": solo afectan caminos que ya terminaban mal. Raíz del worktree = primer worktree de `git worktree list`.
**Lo que encontró la revisión:** `/code-review` encontró 7 hallazgos, todos corregidos con test (salvo el sleep de más): worktree borrado a mano dado por retomado, asignación antes de crear el worktree, asignación sin `--worktree` con la rama en otro worktree, raíz mal con `--separate-git-dir`, número sin validar, sleep de más, docs que nombraban un orquestador inexistente.
**Propuesta:** que `implement-issue` diga explícitamente "asignar al final, después de todo lo que puede fallar" como regla de los scripts que toman issues; el patrón asignar-primero apareció en los dos modos.
