---
name: crear-issue
description: Abre issues de GitHub en este repo a partir de un pedido en el chat, siguiendo la convención del proyecto (título, labels, cuerpo), y marca bloqueos entre issues (dependencias "bloqueado por"). Usar cuando el usuario pida "abrí un issue", "creá un ticket", "anotá esto como bug", "pasá esta auditoría a issues", "esto depende de #12", "bloqueá #30 hasta que se cierre #25", "planificá X", "armá el plan de trabajo para Y", "¿qué puedo hacer ahora?", "¿qué está bloqueado?" o similar.
---

# Crear issue

Convierte un pedido en lenguaje natural en uno o varios issues que cumplen `docs/convencion-nombres-github.md` §4–5, y registra qué issue bloquea a cuál con las dependencias nativas de GitHub. También planifica trabajos grandes (épica + sub-issues + bloqueos) y responde qué se puede empezar ya.

Scripts de esta carpeta (rutas relativas a la skill):
- `disponibles.sh` — qué se puede empezar ya. Solo lee.
- `planificar.py` — valida y crea un plan completo. Requiere `python3`.

## Requisitos

- `gh` autenticado (`gh auth status`). Si no lo está, pedile al usuario que corra `gh auth login`; no sigas.
- `jq` para `disponibles.sh` y `python3` para `planificar.py`.
- Leé `.github/labels.yml` cada vez: es la única lista de labels válida. **Nunca** crees labels nuevos ni uses uno que no esté ahí.

## Pasos

1. **Entender el pedido.** Separá cuántos issues son: un pedido puede traer varios problemas, y una auditoría trae uno por hallazgo. Si falta algo imprescindible (qué falla, o qué hay que lograr), preguntá una sola vez; no inventes datos.
   Detectá también **dependencias**: frases como "depende de", "después de", "primero hay que", "bloqueado por", "cuando esté #12". Anotá cuál bloquea a cuál (ver [Bloqueos](#bloqueos-entre-issues)).

2. **Buscar duplicados.**
   ```bash
   gh issue list --state all --search "<palabras clave>" --limit 10
   ```
   Si hay uno parecido abierto, mostralo y preguntá si comentar ahí en vez de abrir otro.

3. **Elegir el tipo** (exactamente un label `tipo:`):
   | Pedido | Label | Plantilla del cuerpo |
   |---|---|---|
   | Algo no funciona como está definido | `tipo:bug` | `.github/ISSUE_TEMPLATE/1-bug.yml` |
   | Funcionalidad nueva o cambio visible | `tipo:feature` | `2-feature.yml` |
   | Trabajo técnico sin cambio visible | `tipo:task` | `3-task.yml` |
   | Hallazgo de una auditoría | `tipo:audit` | `4-auditoria.yml` |
   | Documentación | `tipo:docs` | `3-task.yml` |

4. **Escribir el título.**
   - Imperativo, sin prefijo ni corchetes, sin punto final, entendible meses después: `Unificar cuentas por email`.
   - Bug: se acepta el síntoma: `El QR no valida sin conexión`.
   - Auditoría: `Auditoría <área>: <hallazgo>`.

5. **Elegir el resto de los labels** (solo de `labels.yml`):
   - `area:` — 1 o 2, según qué parte del producto toca. Si no estás seguro, ninguno.
   - `prioridad:` — solo si el usuario la dio o es obvia (rompe producción, dinero o datos → `prioridad:critica`). Si no, no pongas prioridad y agregá `estado:a-triar`.
   - `logica-negocio` — si pide cambiar una regla ya definida en un ADR, auditoría o plan. Citá cuál en el cuerpo.
   - `breaking-change` — si rompe un contrato público.

6. **Escribir el cuerpo** con las secciones de la plantilla elegida, como Markdown (`## Qué pasa`, `## Qué debería pasar`…). Reglas:
   - Links a archivos con ruta relativa del repo y, si sirve, línea.
   - Si sale de una auditoría o ADR, el link al documento y el ID del hallazgo o regla.
   - Nunca secretos, tokens ni datos personales reales.
   - Al final: `_Abierto desde el chat con Claude Code a pedido de @<usuario>._` (`gh api user -q .login`).

7. **Mostrar el borrador y esperar confirmación.** Abrir un issue publica contenido en el repo. Mostrá título, labels, cuerpo y **bloqueos** (`#B bloqueado por #A`) de cada issue y pedí un "sí" explícito. Con varios issues, mostralos todos juntos y confirmá una vez la tanda.

8. **Crear.** Escribí el cuerpo a un archivo temporal para no romper el escapado:
   ```bash
   gh issue create --title "<título>" --body-file <archivo> \
     --label "tipo:bug" --label "area:api" --label "estado:a-triar"
   ```
   Opcionales, solo si el usuario los pidió: `--assignee @me`, `--milestone "<nombre>"`, `--project "<nombre>"`.

9. **Sub-issues** (épica con tareas): creá primero el padre y después cada hijo, y vinculalos:
   ```bash
   hijo_id=$(gh api repos/{owner}/{repo}/issues/<n_hijo> -q .id)
   gh api repos/{owner}/{repo}/issues/<n_padre>/sub_issues -X POST -F sub_issue_id=$hijo_id
   ```

10. **Bloqueos.** Si hay dependencias, registralas después de crear todos los issues de la tanda (los nuevos todavía no tienen número antes). Ver [Bloqueos entre issues](#bloqueos-entre-issues).

11. **Responder** con el link de cada issue creado y los bloqueos que quedaron. Si algo falló (label inexistente, permisos), decilo con el error; no reintentes con otros labels sin avisar.

## Auditoría → issues

Cuando el pedido es "pasá la auditoría X a issues":
- Un issue por hallazgo, con `tipo:audit` y el título `Auditoría <área>: <hallazgo>`.
- El cuerpo enlaza `docs/development/<auditoría>.md` y el ID del hallazgo (`AUD-07`).
- Si el documento no tiene IDs, proponé agregarlos antes de abrir los issues.
- Después de crearlos, ofrecé anotar el número de issue al lado de cada hallazgo en el documento.

## Bloqueos entre issues

Un issue **bloqueado por** otro no se puede empezar (o terminar) hasta que el otro se cierre. Ejemplo: "Migrar pagos a la tabla nueva" está bloqueado por "Crear la tabla nueva de pagos". GitHub lo muestra en los dos issues ("Blocked by" / "Blocking") y en el Project.

No confundir con sub-issues: un **sub-issue** es una parte del trabajo del padre; un **bloqueo** es un orden entre dos trabajos que pueden ser independientes. Una épica puede tener sub-issues que además se bloquean entre sí.

### Cuándo marcar un bloqueo

- El usuario lo pide ("#30 depende de #25", "no se puede hacer X hasta Y").
- Al crear una tanda donde el orden es obvio (schema antes que migración, API antes que pantalla que la consume). En ese caso **proponelo** en el borrador; no lo marques sin confirmación.
- No lo marques solo porque dos issues tocan la misma área.

### Cómo

Las dependencias usan el `id` interno del issue que bloquea (no el número):

```bash
# #B queda bloqueado por #A
id_a=$(gh api repos/{owner}/{repo}/issues/<A> -q .id)
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by -X POST -F issue_id=$id_a

# Ver qué bloquea a #B y a qué bloquea #A
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by -q '.[] | "#\(.number) \(.state) \(.title)"'
gh api repos/{owner}/{repo}/issues/<A>/dependencies/blocking  -q '.[] | "#\(.number) \(.state) \(.title)"'

# Quitar el bloqueo
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by/$id_a -X DELETE
```

Además:
- Al bloquear un issue **abierto** por otro **abierto**, agregale el label `estado:bloqueado` y una línea al final del cuerpo: `Bloqueado por #A: <por qué>`. El workflow `.github/workflows/desbloquear.yml` saca el label solo cuando se cierran todos sus bloqueantes.
- Si el que bloquea ya está cerrado, no tiene sentido el bloqueo: avisá en vez de crearlo.
- **Sin ciclos.** Antes de crear `B bloqueado por A`, revisá que A no esté bloqueado (directa o indirectamente) por B, recorriendo `blocked_by` de A. Si hay ciclo, no lo crees y explicalo.
- Para bloqueos sobre issues **existentes** (no recién creados), mostrá el cambio (`#B bloqueado por #A`) y pedí confirmación igual que para crear un issue.
- Si la API responde 404 o 422 (repo sin dependencias habilitadas, issue de otro repo sin permiso), decilo con el error y dejá el bloqueo escrito en el cuerpo del issue como respaldo.

## Qué se puede hacer ahora

Para "¿qué puedo hacer ahora?", "¿qué sigue?", "¿qué está bloqueado?":

```bash
.claude/skills/crear-issue/disponibles.sh
```

Devuelve tres listas: **se pueden empezar ya** (sin bloqueantes abiertos, por prioridad), **bloqueados** (con lo que los bloquea) y **épicas en curso** (con avance de sub-issues). Las épicas no aparecen como disponibles: se trabajan por sus sub-issues.

Al responder:
- Mostrá la salida tal cual, sin inventar issues que no están.
- Si el usuario dice en qué área o con qué prioridad quiere trabajar, filtrá la lista con eso.
- Si hay disponibles con `estado:a-triar`, mencionalo: todavía no tienen prioridad.
- GitHub tarda unos segundos en actualizar el resumen de dependencias: si un issue se cerró recién, puede seguir figurando unos segundos más.

No modifica nada, así que no hace falta confirmación.

## Planificar un trabajo grande

Para "planificá la migración de cuentas", "armá los issues para el checkout nuevo": una épica, sus sub-issues y los bloqueos entre ellos, en un solo borrador.

1. **Entender el alcance.** Leé los docs y el código relevantes (`docs/development/architecture.md`, ADRs, módulos). Si el pedido es ambiguo en algo que cambia la división del trabajo, preguntá antes.
2. **Dividir.** Cada sub-issue es un PR razonable: se puede revisar solo y deja el sistema funcionando. Típicamente 3 a 8. Si salen más, proponé dividir en dos épicas.
3. **Ordenar.** Marcá `bloqueado_por` solo cuando un issue de verdad no puede empezar sin el otro (schema → API → pantalla). Lo que se puede hacer en paralelo queda sin bloqueo.
4. **Escribir el plan** en un JSON temporal (fuera del repo):
   ```json
   {
     "epica": {"titulo": "Migrar cuentas a la tabla nueva", "cuerpo": "## Objetivo\n…", "labels": ["tipo:feature", "area:api"]},
     "issues": [
       {"clave": "schema", "titulo": "Crear la tabla de cuentas", "cuerpo": "…", "labels": ["tipo:task", "area:infra"]},
       {"clave": "api", "titulo": "Exponer las cuentas en la API", "cuerpo": "…", "labels": ["tipo:task", "area:api"],
        "bloqueado_por": ["schema"], "motivo": "necesita la tabla"},
       {"clave": "pantalla", "titulo": "Mostrar las cuentas en el panel", "cuerpo": "…", "labels": ["tipo:feature"],
        "bloqueado_por": ["api", 25], "motivo": "consume el endpoint; #25 define el diseño"}
     ]
   }
   ```
   `bloqueado_por` acepta claves del plan o números de issues existentes. Títulos, labels y cuerpos siguen los pasos 3–6 de arriba.
5. **Validar y mostrar el borrador:**
   ```bash
   .claude/skills/crear-issue/planificar.py <plan.json> --borrador
   ```
   Valida labels contra `labels.yml`, exactamente un `tipo:` por issue, claves y números existentes, y que no haya ciclos. Muestra los issues en el orden en que se pueden hacer. Si falla, corregí el plan; no saltees la validación.
   Mostrale al usuario esa salida y pedí un "sí" explícito.
6. **Crear:**
   ```bash
   .claude/skills/crear-issue/planificar.py <plan.json>
   ```
   Crea la épica, cada issue en orden, los vincula como sub-issues, registra los bloqueos, agrega `estado:bloqueado` y la línea `Bloqueado por #N` donde corresponde. Si falla a mitad de camino, informa qué alcanzó a crear: mostralo y no reintentes el plan entero (duplicaría issues); creá solo lo que falta.
7. **Responder** con los links y el orden sugerido de trabajo.
