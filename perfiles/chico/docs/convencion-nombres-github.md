# Convención de GitHub — <PROYECTO>

> Decidido el <FECHA>. Si algo no está cubierto, se pregunta antes de inventar un formato.

## Ramas

<REGLA_RAMAS>

Formato `<tipo>/<n°issue>-<descripcion>` ([Conventional Branch](https://conventionalbranch.org/)): solo minúsculas, números y guiones, sin tildes ni ñ.

| Tipo | Cuándo |
|---|---|
| `feat/` | Funcionalidad nueva |
| `fix/` | Corrección de un bug |
| `chore/` | Dependencias, config, docs, tooling |
| `claude/` | Rama creada por un agente |

## Commits y títulos de PR

[Conventional Commits](https://www.conventionalcommits.org/): `<tipo>: <descripcion>`, en imperativo, minúscula, sin punto final, ≤ 72 caracteres. Tipos: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. Si rompe compatibilidad: `feat!: …`.

## Pull requests

Cuerpo con [la plantilla](../.github/pull_request_template.md) y `Closes #n`. Se mergea con squash. Nadie (ni agentes) pushea directo a la rama troncal.

## Issues

Título en imperativo, sin prefijo: `Agregar login con Google`. Para bugs vale el síntoma: `El formulario no guarda sin conexión`.

## Labels

| Grupo | Valores |
|---|---|
| `tipo:` | `feature`, `bug`, `task`, `docs` — exactamente uno |
| `prioridad:` | `alta`, `media`, `baja` — solo en issues |

Fuente: [`.github/labels.yml`](../.github/labels.yml). No se crean otros.

## Versiones

Si se publican: [SemVer](https://semver.org/) con `v` (`v0.3.0`).
