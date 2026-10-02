---
name: implement-issue
description: Implementa un issue de GitHub de punta a punta, del issue al PR listo para revisar - toma el issue, crea la rama, escribe código y tests, se autorevisa, actualiza los docs y abre el PR. No mergea. Usar con "/implement-issue #43", "implementá el #43", "tomá el siguiente issue".
---

# Implementar issue

Lleva un issue a un PR listo para revisar. **Nunca mergea**: eso lo hace una persona.

Si no te dieron un número ("tomá el siguiente"), listá `gh issue list --state open --search "no:assignee" --label "prioridad:alta"` (después `media`, `baja`, sin prioridad), proponé uno y esperá confirmación.

## 1. Tomar el issue

```bash
.claude/skills/implement-issue/preparar.sh <n>
```

Valida que esté abierto, que no lo tenga otra persona y que no haya cambios sin commitear; lo asigna, crea `claude/<n>-<descripcion>` desde `<RAMA_BASE>` e imprime el issue con sus comentarios. Si falla, contale al usuario por qué; no fuerces nada. Para leerlo sin tomarlo: `--revisar`.

## 2. Entender

- Leé lo que enlaza el issue, `AGENTS.md` y lo que corresponda de `docs/architecture.md` y `docs/decisions/`.
- Si es ambiguo en algo que cambia el resultado, o pide algo de la lista **"Consulta antes"** de `AGENTS.md` sin aprobación en el issue, preguntá antes de escribir código.

## 3. Implementar

- **Bug** (`tipo:bug`) → skill `debug`: causa raíz antes que arreglo.
- **Base de datos** → la sección "Si toca la base de datos" de `AGENTS.md`: plan con rollback aprobado antes de la migración.
- Solo lo que pide el issue. Lo demás, a un issue nuevo (`crear-issue`).
- Commits con la convención (`<tipo>: <descripcion>`).

## 4. Tests

Agregá o ajustá tests que cubran el cambio (en un bug, uno que fallaba antes). Corré lint, typecheck y tests de `AGENTS.md`; si algo falla, arreglalo, no lo desactives.

## 5. Autorevisión

Leé el diff completo (`git diff <RAMA_BASE>...HEAD`) como si fuera de otra persona: bugs, casos borde, código muerto, secretos, archivos de más. Si está disponible `/code-review`, corrélo. Si tocaste algo de "Consulta antes" y está `/security-review`, corrélo también.

## 6. Docs

Skill `update-docs`: si cambió algo que corre, `docs/architecture.md` (y `AGENTS.md` si cambió un comando o una convención) en el mismo PR.

## 7. PR

```bash
git push -u origin HEAD
gh pr create --base <RAMA_BASE> --title "<tipo>: <descripcion>" --body-file <archivo> --label "tipo:..."
```

Cuerpo con `.github/pull_request_template.md`, los comandos que corriste en "Cómo probarlo" y `Closes #<n>`. Mirá el CI (`gh pr checks --watch`) y corregí lo que falle por tu cambio.

## 8. Entregar

Link al PR, qué cambió en dos líneas y qué decisiones tiene que mirar quien revise. Y frená.

Si no podés terminar: comentá en el issue qué hiciste y qué falta, pusheá la rama si sirve y desasignate (`gh issue edit <n> --remove-assignee @me`).
