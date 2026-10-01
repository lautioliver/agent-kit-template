---
name: git-workflow
description: Flujo de ramas, commits y PRs de este repo. Usar siempre que crees ramas, commits, pushes o pull requests.
---

# Git workflow — <PROYECTO>

Detalle en `docs/convencion-nombres-github.md`. Resumen obligatorio en `AGENTS.md`.

## Ramas

- <REGLA_RAMAS> Creá la rama de trabajo desde `<RAMA_BASE>` actualizada.
- Nombre: `claude/<n°issue>-<descripcion>` (agente) o `<tipo>/<n°issue>-<descripcion>` (persona). Solo minúsculas, números y guiones.
- Si no hay issue, preguntá si abrir uno (skill `crear-issue`) antes de inventar el número.

## Commits

- `<tipo>(<scope>): <descripcion>` — imperativo, minúscula, sin punto, ≤ 72 caracteres. Tipos en inglés, descripción en español.
- Un commit = un cambio lógico. Si toca varios scopes, sin scope o dividir.
- Rompe compatibilidad: `feat(api)!: …` + footer `BREAKING CHANGE: …`.

## Pull requests

1. Nunca push directo a las ramas troncales. Todo entra por PR.
2. Título con el mismo formato que un commit.
3. Cuerpo con `.github/pull_request_template.md`: Qué cambia / Por qué / Lógica de negocio afectada / Cómo probarlo / `Closes #n`.
4. Labels: exactamente un `tipo:` (las ramas `claude/` no lo reciben automático: ponelo vos), 1–2 `area:`, ningún `prioridad:`. Solo labels de `.github/labels.yml`.
5. Si cambia una regla de un ADR, auditoría o plan: label `logica-negocio` y explicarlo en "Lógica de negocio afectada".

```bash
gh pr create --base <RAMA_BASE> --title "fix(api): …" --body-file <archivo> --label "tipo:bug" --label "area:api"
```
