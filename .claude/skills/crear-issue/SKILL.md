---
name: crear-issue
description: Abre issues de GitHub en este repo a partir de un pedido en el chat, siguiendo la convención del proyecto (título, labels, cuerpo). Usar cuando el usuario pida "abrí un issue", "creá un ticket", "anotá esto como bug", "pasá esta auditoría a issues" o similar.
---

# Crear issue

Convierte un pedido en lenguaje natural en uno o varios issues que cumplen `docs/convencion-nombres-github.md` §4–5.

## Requisitos

- `gh` autenticado (`gh auth status`). Si no lo está, pedile al usuario que corra `gh auth login`; no sigas.
- Leé `.github/labels.yml` cada vez: es la única lista de labels válida. **Nunca** crees labels nuevos ni uses uno que no esté ahí.

## Pasos

1. **Entender el pedido.** Separá cuántos issues son: un pedido puede traer varios problemas, y una auditoría trae uno por hallazgo. Si falta algo imprescindible (qué falla, o qué hay que lograr), preguntá una sola vez; no inventes datos.

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

7. **Mostrar el borrador y esperar confirmación.** Abrir un issue publica contenido en el repo. Mostrá título, labels y cuerpo de cada issue y pedí un "sí" explícito. Con varios issues, mostralos todos juntos y confirmá una vez la tanda.

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

10. **Responder** con el link de cada issue creado. Si algo falló (label inexistente, permisos), decilo con el error; no reintentes con otros labels sin avisar.

## Auditoría → issues

Cuando el pedido es "pasá la auditoría X a issues":
- Un issue por hallazgo, con `tipo:audit` y el título `Auditoría <área>: <hallazgo>`.
- El cuerpo enlaza `docs/development/<auditoría>.md` y el ID del hallazgo (`AUD-07`).
- Si el documento no tiene IDs, proponé agregarlos antes de abrir los issues.
- Después de crearlos, ofrecé anotar el número de issue al lado de cada hallazgo en el documento.
