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
| Issues | `.github/ISSUE_TEMPLATE/*.yml` (formularios con labels automáticos) |
| Skills de Claude Code | `.claude/skills/crear-issue` (abrir issues desde el chat), `.claude/skills/git-workflow` |

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
3. Completá lo que está marcado con `TODO:`. Buscalo con `grep -rn "TODO:" .`. Lo mínimo:
   - `AGENTS.md`: qué es, stack, comandos y convenciones de código.
   - `.github/labels.yml` y `.github/labeler.yml`: los labels `area:` y las rutas de tu repo.
   - `docs/convencion-nombres-github.md` §2: los scopes de commit.
4. Corré el workflow **Labels** a mano (Actions → Labels → Run workflow) para crear los labels en el repo.
5. Si usás Cursor, copiá o enlazá las skills: `ln -s ../.claude/skills .cursor/skills`.

## Abrir issues desde el chat

Con Claude Code en el repo, pedilo en lenguaje natural:

> abrí un issue: el QR no valida sin conexión, es urgente

La skill `crear-issue` arma el título según la convención, elige labels que existan en `labels.yml`, busca duplicados, te muestra el borrador y lo crea con `gh` cuando lo confirmás. También sirve para pasar una auditoría a issues: un issue por hallazgo.

Necesita `gh` instalado y autenticado (`gh auth status`).
