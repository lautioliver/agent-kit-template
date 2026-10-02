# Plantilla de repo: reglas para agentes + documentación

Repo plantilla para arrancar proyectos con una estructura de documentación y reglas para LLMs lista para usar.

## Qué trae

| Pieza | Archivos |
|---|---|
| Reglas para agentes | `AGENTS.md` (fuente), `CLAUDE.md` (apunta a AGENTS.md), `llms.txt`, `docs/llms.txt` |
| Hub de documentación | `docs/README.md` + `reference/`, `development/`, `guides/`, `decisions/` |
| ADRs | `docs/decisions/README.md` (cómo se escriben) + `ADR-000-plantilla.md` |
| Convenciones de GitHub | `docs/convencion-nombres-github.md` (ramas, commits, PRs, issues, labels) |
| Labels | `.github/labels.yml` (fuente), `.github/labeler.yml` (auto-etiquetado de PRs), `.github/workflows/labels.yml` (sync + labeler + check) |
| PRs | `.github/pull_request_template.md` |
| Issues | `.github/ISSUE_TEMPLATE/*.yml` (formularios con labels automáticos), `.github/workflows/desbloquear.yml` (saca `estado:bloqueado` al cerrarse los bloqueantes) |
| Skills de Claude Code | Ver [El flujo con agentes](#el-flujo-con-agentes) |
| Autonomía del agente | `AGENTS.md` → qué puede hacer solo, qué tiene que consultar y qué nunca |
| Mapa para agentes | `docs/mapa-agentes.json` → qué docs revisar según lo que cambia, rutas sensibles, docs obligatorios |
| Docs testeados en CI | `.github/workflows/docs.yml` + `scripts/agentes/check-docs.py` → links, rutas y ADRs rotos |

## Requisitos

- **GitHub con sub-issues y dependencias de issues** ("Blocked by" / "Blocking") habilitados. Son funciones nuevas de GitHub: si el repo o el plan no las tiene, las skills avisan con el error (404/422) y dejan el bloqueo escrito en el cuerpo del issue, pero `planificar.py`, `disponibles.sh`, `preparar.sh` y el workflow `desbloquear.yml` pierden la parte automática.
- `gh` autenticado, `jq` y `python3` en la máquina donde corre el agente.

## Cómo usarla

1. En GitHub: **Use this template → Create a new repository**.
2. Cloná el repo nuevo y corré:

   ```bash
   ./scripts/init-plantilla.sh "Nombre del proyecto" main
   ```

   El segundo argumento es la rama base de los PRs:

   | Opción | Flujo | Cuándo |
   |---|---|---|
   | `main` | rama → `main` | Proyecto nuevo, sin usuarios todavía |
   | `develop` | rama → `develop` → `main` | Separar integración de producción |
   | `develop releases` | rama → `develop` → `release/vX.Y.Z` → `main` | La app ya tiene usuarios activos: cada versión se congela y se prueba en staging antes de llegar a producción |

   Ejemplo con releases: `./scripts/init-plantilla.sh "Nombre del proyecto" develop releases`. El script pone el nombre, la rama base, la regla de ramas que corresponde y la fecha de hoy como fecha de las decisiones. Después se borra solo.

   **Proyecto chico** (una o dos personas): agregá `--chico`, por ejemplo `./scripts/init-plantilla.sh "Nombre del proyecto" main --chico`.

   | | Completo | `--chico` |
   |---|---|---|
   | Skills | 9 | 4: `implement-issue`, `crear-issue`, `debug`, `update-docs` |
   | Workflows | 4 | 2: docs y sync de labels |
   | Labels | `tipo:`, `area:`, `prioridad:`, `estado:` y especiales | 7: `tipo:` y `prioridad:` |
   | Docs | hub con `reference/`, `development/`, `guides/` | un solo archivo de arquitectura y los ADRs |
   | Convención de GitHub | documento con opciones y decisiones | una página con las reglas |
   | Autonomía y rutas sensibles | `AGENTS.md` + `docs/mapa-agentes.json` | todo en `AGENTS.md`, con la checklist de migraciones |
   | Sale | | épicas y `plan-feature`, `review-pr`, `estado`, bloqueos, labeler, formularios de issue, modo releases |

   Los archivos del modo chico están en `perfiles/chico/` (más la lista `BORRAR`); el init los aplica y borra la carpeta. Lo común (skills como `debug`, `check-docs.py`, `preparar.sh`) es el mismo archivo en los dos modos, así los arreglos llegan a ambos.
3. Completá lo que está marcado con `TODO:`. Lo más importante para los agentes es `docs/mapa-agentes.json`: poné las rutas reales de schema, auth, pagos y API pública. Hasta que no quede ningún `TODO/` ahí, el check de docs en CI falla a propósito: con rutas de ejemplo, el agente nunca detectaría que tocó algo sensible. Buscalo con `grep -rn "TODO:" .`. Lo mínimo:
   - `AGENTS.md`: qué es, stack, comandos y convenciones de código.
   - `.github/labels.yml` y `.github/labeler.yml`: los labels `area:` y las rutas de tu repo.
   - `docs/convencion-nombres-github.md` §2: los scopes de commit.
4. Corré el workflow **Labels** a mano (Actions → Labels → Run workflow) para crear los labels en el repo.
5. Si usás Cursor, copiá o enlazá las skills: `ln -s ../.claude/skills .cursor/skills`.

## Abrir issues desde el chat

Con Claude Code en el repo, pedilo en lenguaje natural:

> abrí un issue: el QR no valida sin conexión, es urgente

La skill `crear-issue` arma el título según la convención, elige labels que existan en `labels.yml`, busca duplicados, te muestra el borrador y lo crea con `gh` cuando lo confirmás. También sirve para pasar una auditoría a issues (un issue por hallazgo) y para marcar bloqueos:

> la migración de pagos depende de que se cierre #25

La skill registra la dependencia nativa de GitHub ("Blocked by"), pone `estado:bloqueado` y el workflow `desbloquear.yml` saca el label solo cuando se cierran todos los bloqueantes.

Y para trabajos más grandes:

> planificá la migración de cuentas

arma una épica con sus sub-issues y los bloqueos entre ellos, te muestra el borrador en el orden en que se pueden hacer y lo crea al confirmar.

> ¿qué puedo hacer ahora?

lista los issues sin bloqueantes abiertos por prioridad, los bloqueados con lo que los bloquea y el avance de cada épica.

Necesita `gh` instalado y autenticado (`gh auth status`).

## El flujo con agentes

```
idea → /plan-feature → épica + issues con bloqueos
     → /implement-issue <n>
         [debug si es bug · db-migration si toca schema · tests · autorevisión · update-docs]
     → PR → /review-pr <n> (otra sesión) [+ /security-review si toca rutas sensibles]
     → merge (una persona)
```

| Skill | Para qué |
|---|---|
| `/plan-feature` | Investiga código, arquitectura y ADRs, arma un plan técnico y lo convierte en épica + issues. No escribe código. |
| `crear-issue` | Issues sueltos, auditoría → issues, bloqueos entre issues existentes. |
| `/implement-issue <n>` | Del issue al PR: toma el issue, rama, código, tests, autorevisión, docs, PR. No mergea. |
| `debug` | Síntoma → evidencia → causa raíz → arreglo → test de regresión. |
| `db-migration` | Plan con compatibilidad, backfill y rollback antes de tocar el schema. |
| `update-docs` | Qué docs quedaron viejos por un cambio (según el mapa) y corregirlos en el mismo PR. |
| `/review-pr <n>` | Revisión con foco en lo propio del proyecto: reglas de negocio, ADRs, autonomía, docs, tests, rutas sensibles. No aprueba. |
| `/estado` | Resumen del proyecto generado en el momento (versión, trabajo, épicas, PRs, deuda, decisiones, migraciones) y "¿qué puedo hacer ahora?" (`disponibles.sh`). |
| `git-workflow` | Ramas, commits y PRs. |

Dos puntos de control quedan siempre en manos de personas: **aprobar el plan** y **mergear**.
