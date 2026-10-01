# AGENTS.md — <PROYECTO>

Contexto rápido para agentes y devs que tocan este repo. Es la fuente de las reglas para LLMs: `CLAUDE.md` solo lo importa.

## Qué es

TODO: una o dos frases. Qué hace el producto y la decisión más importante que lo define (con link a su ADR).

Índice de docs (humanos + LLMs): `docs/README.md`. Spec: `README.md`. Narrativa: `docs/development/vision.md`. Qué corre hoy: `docs/development/architecture.md`. Orden de trabajo: `docs/development/roadmap.md`. Largo plazo (no construir): `docs/development/horizon.md`.

## Stack

TODO: lenguaje, framework, base de datos, monorepo, tests. Una línea por pieza.

## Comandos

```bash
# TODO: instalar, typecheck, lint, test, dev
```

TODO: comandos que NO se corren (por ejemplo builds de producción) y por qué.

## Convenciones que importan

TODO: las reglas de código que un agente rompería si no las lee. Ejemplos:
- Errores de API con un formato único.
- IDs públicos con prefijo, nunca secuenciales.
- Dinero en enteros (centavos).
- Lógica de negocio en servicios, rutas finas.
- Operaciones concurrentes atómicas en la base, nunca read-modify-write.

Siempre:
- Nunca secretos en logs, código o repo. `.env*` están ignorados.
- Si un documento y el código no coinciden, gana el código y se actualiza el documento.

## Convenciones de GitHub (obligatorio)

Fuente de verdad: `docs/convencion-nombres-github.md`. Labels: `.github/labels.yml`. Solo lo marcado como decidido en su §12 es obligatorio. Lo que no esté decidido o cubierto se le pregunta al equipo antes de inventar un formato.

- **Ramas:** Conventional Branch 1.1, `<tipo>/<n°issue>-<descripcion>`. Tipos: `feat`, `fix`, `hotfix`, `chore`, `release`. Si la crea un agente: `claude/<n°issue>-<descripcion>`. Solo minúsculas, números y guiones, sin tildes ni ñ.
- **Rama base:** <REGLA_RAMAS> Ver la skill `git-workflow`.
- **Commits y títulos de PR:** Conventional Commits 1.0, `<tipo>(<scope>): <descripcion>`, en imperativo, minúscula, sin punto final, ≤ 72 caracteres. Tipos en inglés; descripción en español.
- **Scopes:** los de `docs/convencion-nombres-github.md` §2. Si un cambio toca varios, se omite el scope o se divide en varios commits.
- **Cuerpo del PR:** `.github/pull_request_template.md` (Qué cambia / Por qué / Lógica de negocio afectada / Cómo probarlo / `Closes #n`).
- **Labels:** prefijo `grupo:valor` (`tipo:`, `area:`, `prioridad:`, `estado:`, más `logica-negocio` y `breaking-change`). Solo los de `.github/labels.yml`; no crear otros.
- **Lógica de negocio:** si el PR cambia una regla ya definida (ADR, auditoría o plan), va el label `logica-negocio` y se explica en el PR.
- **Issues:** se abren con la skill `crear-issue`. Título en imperativo y sin prefijo; el tipo va en el label `tipo:`. Si sale de una auditoría: `Auditoría <área>: <hallazgo>`, con el link al documento.
- **Decisiones irreversibles:** ADR nuevo en `docs/decisions/` (ver su README).

Nada entra a las ramas troncales sin PR.

## Docs

- `docs/README.md` — hub (cómo leer, capas de verdad)
- `docs/llms.txt` — índice compacto para modelos
- `docs/convencion-nombres-github.md` — ramas, commits, PRs, issues, labels
- `docs/reference/` — glosario, dominio, superficies, módulos, recorridos
- `docs/development/` — setup, arquitectura, visión, roadmap, horizonte, deploy, auditorías
- `docs/guides/` — integraciones y guías de uso
- `docs/decisions/` — ADRs
